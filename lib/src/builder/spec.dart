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

/// Data classes for builder specifications.
///
/// These classes represent the discovered parameters and endpoints
/// extracted from source code by the AST visitor.
library;

import 'package:analyzer/dart/ast/ast.dart';

/// Specification for a parameter.
class ParamSpec {
  ParamSpec({
    required this.name,
    required this.type,
    this.options,
    this.format,
  });
  final String name;
  final String type;
  final ParamOptions? options;
  final String? format; // 'json' for JSON secrets
}

/// Options for a parameter.
class ParamOptions {
  ParamOptions({this.defaultValue, this.label, this.description});
  final Object? defaultValue;
  final String? label;
  final String? description;
}

/// Specification for an endpoint (function).
class EndpointSpec {
  EndpointSpec({
    required this.name,
    required this.type,
    this.topic,
    this.firestoreEventType,
    this.documentPath,
    this.database,
    this.namespace,
    this.databaseEventType,
    this.refPath,
    this.instance,
    this.alertType,
    this.appId,
    this.blockingEventType,
    this.idToken,
    this.accessToken,
    this.refreshToken,
    this.schedule,
    this.timeZone,
    this.retryConfig,
    this.storageBucket,
    this.storageEventType,
    this.taskQueueRetryConfig,
    this.taskQueueRateLimits,
    this.eventarcEventType,
    this.eventarcChannel,
    this.eventarcFilters,
    this.globalOptions,
    this.options,
    this.variableToParamName = const {},
  });
  final String name;
  // 'https', 'callable', 'pubsub', 'firestore', 'database', 'alert', 'blocking', 'scheduler', 'storage', 'taskQueue'
  final String type;
  final String? topic; // For Pub/Sub functions
  final String? firestoreEventType; // For Firestore: onDocumentCreated, etc.
  final String? documentPath; // For Firestore: users/{userId}
  final String? database; // For Firestore: (default) or database name
  final String? namespace; // For Firestore: (default) or namespace
  final String? databaseEventType; // For Database: onValueCreated, etc.
  final String? refPath; // For Database: /users/{userId}
  final String? instance; // For Database: database instance or '*'
  final String? alertType; // For Alerts: crashlytics.newFatalIssue, etc.
  final String? appId; // For Alerts: optional app ID filter
  final String? blockingEventType; // For Identity: beforeCreate, etc.
  final bool? idToken; // For Identity: pass ID token
  final bool? accessToken; // For Identity: pass access token
  final bool? refreshToken; // For Identity: pass refresh token
  final String? schedule; // For Scheduler: cron expression
  final String? timeZone; // For Scheduler: timezone
  final Map<String, dynamic>? retryConfig; // For Scheduler: retry configuration
  final String? storageBucket; // For Storage: bucket name
  final String? storageEventType; // For Storage: onObjectFinalized, etc.
  final Map<String, dynamic>?
  taskQueueRetryConfig; // For Tasks: retry configuration
  final Map<String, dynamic>? taskQueueRateLimits; // For Tasks: rate limits
  final String? eventarcEventType; // For Eventarc: custom event type
  final String? eventarcChannel; // For Eventarc: channel ID
  final Map<String, String>? eventarcFilters; // For Eventarc: event filters
  final InstanceCreationExpression? globalOptions;
  final InstanceCreationExpression? options;
  final Map<String, String> variableToParamName;

  /// Extracts options configuration from the AST.
  Map<String, dynamic> extractOptions() {
    final result = _extractOptions(globalOptions);
    final endpointOptions = _extractOptions(options);

    for (final entry in endpointOptions.entries) {
      if (identical(entry.value, _resetOption)) {
        result.remove(entry.key);
      } else {
        result[entry.key] = entry.value;
      }
    }

    return result..removeWhere((_, value) => identical(value, _resetOption));
  }

  static const Object _resetOption = Object();

  Map<String, dynamic> _extractOptions(InstanceCreationExpression? options) {
    if (options == null) return {};

    final result = <String, dynamic>{};

    for (final arg in options.argumentList.arguments) {
      if (arg is! NamedExpression) continue;

      final name = arg.name.label.name;
      final expr = arg.expression;

      // Helper to reduce boilerplate: only adds to map if value exists
      void add(String key, dynamic Function(Expression expr) func) {
        final value = _isResetOption(expr) ? _resetOption : func(expr);
        if (value != null) result[key] = value;
      }

      switch (name) {
        case 'memory':
          add('availableMemoryMb', _extractMemory);
        case 'cpu':
          add('cpu', _extractCpu);
        case 'enforceAppCheck':
          // Runtime-only option for callable functions.
          break;
        case 'timeoutSeconds':
          add('timeoutSeconds', _extractTimeoutSeconds);
        case 'minInstances':
          add('minInstances', _extractInt);
        case 'maxInstances':
          add('maxInstances', _extractInt);
        case 'concurrency':
          add('concurrency', _extractInt);
        case 'region':
          add('region', _extractRegion);
        case 'serviceAccount':
          add('serviceAccount', _extractString);
        case 'vpcConnector':
          add('vpcConnector', _extractString);
        case 'vpcConnectorEgressSettings':
          add('vpcConnectorEgressSettings', _extractVpcEgressSettings);
        case 'ingressSettings':
          add('ingressSettings', _extractIngressSettings);
        case 'invoker':
          add('invoker', _extractInvoker);
        case 'secrets':
          add('secretEnvironmentVariables', _extractSecrets);
        case 'labels':
          add('labels', _extractLabels);
        case 'omit':
          add('omit', _extractBool);

        // Runtime-only options (not exported to manifest):
        // - cors: Handled by Functions Framework at runtime
        // - enforceAppCheck: Runtime App Check validation
        // - consumeAppCheckToken: Runtime App Check replay protection
        // - heartBeatIntervalSeconds: Runtime streaming keepalive
        // - preserveExternalChanges: Deployment behavior, not function config
        case 'cors':
        case 'preserveExternalChanges':
        case 'consumeAppCheckToken':
        case 'heartBeatIntervalSeconds':
          // Intentionally skip these - they're not in the manifest
          break;
      }
    }

    return result;
  }

  bool _isResetOption(Expression expression) =>
      expression is InstanceCreationExpression &&
      // `name` is preferred, but resolved/synthetic ASTs can represent
      // typedef-backed constructors without it.
      (expression.constructorName.name?.name == 'reset' ||
          expression.constructorName.toSource().endsWith('.reset'));

  /// Extracts Memory option value.
  Object? _extractMemory(Expression expression) {
    // Check if it's Memory.param() - generate CEL
    if (expression is InstanceCreationExpression &&
        expression.constructorName.name?.name == 'param') {
      return _extractParamReference(expression);
    }

    // Check if it's Memory.expression() - generate CEL from expression
    if (expression is InstanceCreationExpression &&
        expression.constructorName.name?.name == 'expression') {
      return _extractCelExpression(
        expression.argumentList.arguments.firstOrNull,
      );
    }

    // Check if it's Memory.reset()
    if (expression is InstanceCreationExpression &&
        expression.constructorName.name?.name == 'reset') {
      return null; // Reset means use default
    }

    // Extract literal value: Memory(MemoryOption.mb256) or Memory(.mb256)
    final args = _extractCallArguments(expression);
    final enumName = _extractEnumValueName(args?.firstOrNull);
    if (enumName != null) return _memoryOptionToInt(enumName);

    return null;
  }

  /// Converts MemoryOption enum to integer value.
  int? _memoryOptionToInt(String optionName) => switch (optionName) {
    'mb128' => 128,
    'mb256' => 256,
    'mb512' => 512,
    'gb1' => 1024,
    'gb2' => 2048,
    'gb4' => 4096,
    'gb8' => 8192,
    'gb16' => 16384,
    'gb32' => 32768,
    _ => null,
  };

  /// Extracts CPU option value.
  Object? _extractCpu(Expression expression) {
    // Check if it's Cpu.gcfGen1()
    if (expression is InstanceCreationExpression &&
        expression.constructorName.name?.name == 'gcfGen1') {
      return 'gcf_gen1';
    }

    // Check if it's Cpu.param() - generate CEL
    if (expression is InstanceCreationExpression &&
        expression.constructorName.name?.name == 'param') {
      return _extractParamReference(expression);
    }

    // Check if it's Cpu.reset()
    if (expression is InstanceCreationExpression &&
        expression.constructorName.name?.name == 'reset') {
      return null;
    }

    // Extract literal double value: Cpu(1.0)
    final args = _extractCallArguments(expression);
    return switch (args?.firstOrNull) {
      final DoubleLiteral d => d.value,
      final IntegerLiteral i => i.value,
      _ => null,
    };
  }

  /// Extracts Region option value.
  Object? _extractRegion(Expression expression) {
    // Check if it's Region.param() - generate CEL
    if (expression is InstanceCreationExpression &&
        expression.constructorName.name?.name == 'param') {
      return _extractParamReference(expression);
    }

    // Extract literal value: Region(SupportedRegion.usCentral1) or Region(.usCentral1)
    final args = _extractCallArguments(expression);
    return _extractRegionLiteral(args?.firstOrNull);
  }

  /// Extracts a literal region option from an enum expression.
  Object? _extractRegionLiteral(Expression? expression) {
    final enumName = _extractEnumValueName(expression);
    if (enumName != null) {
      final regionString = _regionEnumToString(enumName);
      return regionString != null ? [regionString] : null;
    }

    return null;
  }

  /// Converts SupportedRegion enum to string value.
  String? _regionEnumToString(String enumName) {
    // Convert camelCase to kebab-case
    return switch (enumName) {
      'asiaEast1' => 'asia-east1',
      'asiaEast2' => 'asia-east2',
      'asiaNortheast1' => 'asia-northeast1',
      'asiaNortheast2' => 'asia-northeast2',
      'asiaNortheast3' => 'asia-northeast3',
      'asiaSouth1' => 'asia-south1',
      'asiaSoutheast1' => 'asia-southeast1',
      'asiaSoutheast2' => 'asia-southeast2',
      'australiaSoutheast1' => 'australia-southeast1',
      'europeCentral2' => 'europe-central2',
      'europeNorth1' => 'europe-north1',
      'europeWest1' => 'europe-west1',
      'europeWest2' => 'europe-west2',
      'europeWest3' => 'europe-west3',
      'europeWest4' => 'europe-west4',
      'europeWest6' => 'europe-west6',
      'northAmericaNortheast1' => 'northamerica-northeast1',
      'southAmericaEast1' => 'southamerica-east1',
      'usCentral1' => 'us-central1',
      'usEast1' => 'us-east1',
      'usEast4' => 'us-east4',
      'usWest1' => 'us-west1',
      'usWest2' => 'us-west2',
      'usWest3' => 'us-west3',
      'usWest4' => 'us-west4',
      _ => null,
    };
  }

  /// Extracts timeout seconds.
  Object? _extractTimeoutSeconds(Expression expression) =>
      _extractInt(expression);

  /// Extracts integer option value.
  Object? _extractInt(Expression expression) {
    if (expression is IntegerLiteral) {
      return expression.value;
    }

    if (expression is InstanceCreationExpression) {
      // Check if it's Option.param() - generate CEL
      if (expression.constructorName.name?.name == 'param') {
        return _extractParamReference(expression);
      }
    }

    // Extract literal: Option(123)
    final args = _extractCallArguments(expression);
    if (args?.firstOrNull case final IntegerLiteral firstArg) {
      return firstArg.value;
    }

    return null;
  }

  /// Extracts string option value.
  Object? _extractString(Expression expression) {
    if (expression is StringLiteral) {
      return expression.stringValue;
    }

    if (expression is InstanceCreationExpression) {
      // Check if it's Option.param() - generate CEL
      if (expression.constructorName.name?.name == 'param') {
        return _extractParamReference(expression);
      }
    }

    // Extract literal: Option('value')
    final args = _extractCallArguments(expression);
    if (args?.firstOrNull case final StringLiteral firstArg) {
      return firstArg.stringValue;
    }

    return null;
  }

  /// Extracts boolean option value.
  Object? _extractBool(Expression expression) {
    if (expression is BooleanLiteral) {
      return expression.value;
    }

    if (expression is InstanceCreationExpression) {
      // Check if it's Option.param() - generate CEL
      if (expression.constructorName.name?.name == 'param') {
        return _extractParamReference(expression);
      }
    }

    // Extract literal: Option(true)
    final args = _extractCallArguments(expression);
    if (args?.firstOrNull case final BooleanLiteral firstArg) {
      return firstArg.value;
    }

    return null;
  }

  /// Extracts VPC egress settings.
  Object? _extractVpcEgressSettings(Expression expression) {
    final args = _extractCallArguments(expression);
    final enumName = _extractEnumValueName(args?.firstOrNull);
    if (enumName != null) {
      return switch (enumName) {
        'privateRangesOnly' => 'PRIVATE_RANGES_ONLY',
        'allTraffic' => 'ALL_TRAFFIC',
        _ => null,
      };
    }

    return null;
  }

  /// Extracts ingress settings.
  Object? _extractIngressSettings(Expression expression) {
    final args = _extractCallArguments(expression);
    final enumName = _extractEnumValueName(args?.firstOrNull);
    if (enumName != null) {
      return switch (enumName) {
        'allowAll' => 'ALLOW_ALL',
        'allowInternalOnly' => 'ALLOW_INTERNAL_ONLY',
        'allowInternalAndGclb' => 'ALLOW_INTERNAL_AND_GCLB',
        _ => null,
      };
    }

    return null;
  }

  /// Extracts invoker list.
  Object? _extractInvoker(Expression expression) {
    // Check for special factories
    if (expression is InstanceCreationExpression &&
        expression.constructorName.name?.name == 'public') {
      return ['public'];
    }
    if (expression is InstanceCreationExpression &&
        expression.constructorName.name?.name == 'private') {
      return ['private'];
    }

    // Extract literal list
    final args = _extractCallArguments(expression);
    if (args?.firstOrNull case final ListLiteral firstArg) {
      return firstArg.elements
          .whereType<StringLiteral>()
          .map((e) => e.stringValue)
          .nonNulls
          .toList();
    }

    return null;
  }

  /// Extracts secrets list.
  List<String>? _extractSecrets(Expression expression) {
    if (expression is! ListLiteral) return null;

    final secrets = <String>[];
    for (final element in expression.elements) {
      if (element is Expression) {
        final secretName = _extractSecretName(element);
        if (secretName != null) secrets.add(secretName);
      }
    }

    return secrets.isEmpty ? null : secrets;
  }

  /// Extracts secret name from SecretParam instance.
  String? _extractSecretName(Expression expression) {
    if (expression is! SimpleIdentifier) return null;

    // The identifier references a SecretParam variable
    // We need to find its definition, but for now just use the variable name
    return expression.name;
  }

  /// Extracts labels map.
  Object? _extractLabels(Expression expression) {
    if (expression is! SetOrMapLiteral) return null;
    if (!expression.isMap) return null;

    final labels = <String, String>{};
    for (final element in expression.elements) {
      if (element is MapLiteralEntry) {
        final key = element.key;
        final value = element.value;

        if (key is StringLiteral && value is StringLiteral) {
          labels[key.stringValue!] = value.stringValue!;
        }
      }
    }

    return labels.isEmpty ? null : labels;
  }

  /// Extracts parameter reference and generates CEL expression.
  String _extractParamReference(InstanceCreationExpression expression) {
    final args = expression.argumentList.arguments;
    if (args.isEmpty) return '{{ params.UNKNOWN }}';

    final firstArg = args.first;
    if (firstArg is SimpleIdentifier) {
      // Look up the actual param name from the mapping
      final variableName = firstArg.name;
      final paramName =
          variableToParamName[variableName] ?? toUpperSnakeCase(variableName);
      return '{{ params.$paramName }}';
    }

    return '{{ params.UNKNOWN }}';
  }

  /// Extracts a CEL expression from an expression argument.
  /// Handles thenElse (ternary) expressions on boolean params.
  String? _extractCelExpression(Expression? expression) {
    // Handle method invocation like: isProduction.thenElse(2048, 512)
    if (expression is MethodInvocation) {
      final target = expression.target;
      final methodName = expression.methodName.name;

      if (methodName == 'thenElse' && target is SimpleIdentifier) {
        // Get the param name from the variable
        final variableName = target.name;
        final paramName =
            variableToParamName[variableName] ?? toUpperSnakeCase(variableName);

        // Extract the two arguments
        final args = expression.argumentList.arguments;
        if (args.length >= 2) {
          final trueValue = _extractLiteralValue(args[0]);
          final falseValue = _extractLiteralValue(args[1]);
          if (trueValue != null && falseValue != null) {
            return '{{ params.$paramName ? $trueValue : $falseValue }}';
          }
        }
      }
    }

    return null;
  }

  /// Extracts a literal value from an expression.
  Object? _extractLiteralValue(Expression expression) => switch (expression) {
    StringLiteral() => '"${expression.stringValue}"',
    IntegerLiteral() => expression.value,
    DoubleLiteral() => expression.value,
    BooleanLiteral() => expression.value,
    _ => null,
  };

  /// Extracts arguments from constructor-like calls. When code is unresolved,
  /// wrappers such as `DeployOption(...)` can appear as invocations instead of
  /// [InstanceCreationExpression] nodes.
  NodeList<Expression>? _extractCallArguments(
    Expression expression,
  ) => switch (expression) {
    InstanceCreationExpression(:final argumentList) => argumentList.arguments,
    FunctionExpressionInvocation(:final argumentList) => argumentList.arguments,
    MethodInvocation(target: null, :final argumentList) =>
      argumentList.arguments,
    _ => null,
  };

  /// Extracts an enum value name from an expression, handling both
  /// fully-qualified (`SupportedRegion.europeWest3`) and shorthand
  /// (`.europeWest3`) syntax.
  String? _extractEnumValueName(Expression? expression) => switch (expression) {
    PrefixedIdentifier() => expression.identifier.name,
    SimpleIdentifier() => expression.name,
    PropertyAccess() => expression.propertyName.name,
    DotShorthandPropertyAccess() => expression.propertyName.name,
    _ => null,
  };
}

/// Converts a camelCase or PascalCase string to UPPER_SNAKE_CASE.
String toUpperSnakeCase(String input) {
  return input
      .replaceAllMapped(RegExp(r'[A-Z]'), (match) => '_${match.group(0)}')
      .toUpperCase()
      .replaceFirst('_', '');
}
