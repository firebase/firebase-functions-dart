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

/// Build-time code generator for Firebase Functions.
///
/// This builder analyzes Dart source code to discover function declarations
/// and their configurations, then generates a functions.yaml manifest that
/// firebase-tools uses for deployment.
///
/// See BUILDER_SYSTEM.md for detailed documentation.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:source_gen/source_gen.dart';

import 'src/builder/manifest.dart';
import 'src/builder/spec.dart';

/// Builder factory function (called by build_runner).
Builder specBuilder(BuilderOptions options) => _SpecBuilder();

/// The main builder that generates functions.yaml.
class _SpecBuilder implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => {
    r'$package$': ['functions.yaml'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final resolver = buildStep.resolver;

    // Find all Dart files in the package
    final assets = await buildStep.findAssets(Glob('**.dart')).toSet();

    final allParams = <String, ParamSpec>{};
    final allEndpoints = <String, EndpointSpec>{};

    // Pass 1: collect all top-level options variable declarations across every
    // file into a shared map, and cache each parsed AST for reuse in pass 2.
    // This enables cross-file resolution — e.g. options declared in
    // shared_options.dart can be referenced in server.dart.
    final sharedOptionsVars = <String, InstanceCreationExpression>{};
    final astCache = <AssetId, CompilationUnit>{};

    for (final asset in assets) {
      if (asset.package != buildStep.inputId.package) continue;
      LibraryElement library;
      try {
        library = await resolver.libraryFor(asset, allowSyntaxErrors: true);
      } catch (e) {
        continue;
      }
      final fragment = library.firstFragment;
      final astNode = await resolver.astNodeFor(fragment, resolve: true);
      if (astNode is! CompilationUnit) continue;
      astCache[asset] = astNode;
      astNode.accept(_OptionsVariableCollector(sharedOptionsVars));
    }

    final globalOptionsCollector = _GlobalOptionsCollector(sharedOptionsVars);
    for (final ast in astCache.values) {
      ast.accept(globalOptionsCollector);
    }
    final globalOptions = globalOptionsCollector.globalOptions;

    // Pass 2: visit each file with the shared options map so that variable
    // references to options declared in other files can be resolved.
    for (final entry in astCache.entries) {
      final visitor = _FirebaseFunctionsVisitor(
        sharedOptionsVars,
        globalOptions: globalOptions,
      );
      entry.value.accept(visitor);
      allParams.addAll(visitor.params);
      allEndpoints.addAll(visitor.endpoints);
    }

    // Generate YAML from collected data
    final yamlContent = generateManifestYaml(allParams, allEndpoints);

    // Write the YAML file
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'functions.yaml'),
      '$yamlContent\n',
    );
  }
}

const _pkg = 'package:firebase_functions';

class _Namespace {
  const _Namespace(this.extractor, this.typeChecker, this.methodNames);

  final String typeChecker;
  final void Function(MethodInvocation, String) extractor;
  final List<String> methodNames;

  bool isNamespace(Expression target) {
    final staticType = target.staticType;
    if (staticType == null) return false;
    return TypeChecker.fromUrl(typeChecker).isExactlyType(staticType);
  }

  bool matches(String methodName) => methodNames.contains(methodName);
}

/// Lightweight AST visitor that collects top-level variable declarations whose
/// initializers are [InstanceCreationExpression]s into [variableToOptionsExpr].
/// Used in a pre-pass over all files to enable cross-file options resolution.
class _OptionsVariableCollector extends RecursiveAstVisitor<void> {
  _OptionsVariableCollector(this.variableToOptionsExpr);

  final Map<String, InstanceCreationExpression> variableToOptionsExpr;

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    for (final variable in node.variables.variables) {
      final initializer = variable.initializer;
      if (initializer is InstanceCreationExpression) {
        variableToOptionsExpr[variable.name.lexeme] = initializer;
      }
    }
    super.visitTopLevelVariableDeclaration(node);
  }
}

/// Collects the expression passed to `setGlobalOptions(...)`.
class _GlobalOptionsCollector extends RecursiveAstVisitor<void> {
  _GlobalOptionsCollector(this.variableToOptionsExpr);

  final Map<String, InstanceCreationExpression> variableToOptionsExpr;
  InstanceCreationExpression? globalOptions;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null && node.methodName.name == 'setGlobalOptions') {
      final firstArg = node.argumentList.arguments.firstOrNull;
      if (firstArg is InstanceCreationExpression) {
        globalOptions = firstArg;
      } else if (firstArg is SimpleIdentifier) {
        globalOptions = variableToOptionsExpr[firstArg.name] ?? globalOptions;
      }
    }
    super.visitMethodInvocation(node);
  }
}

/// AST visitor that discovers Firebase Functions declarations.
class _FirebaseFunctionsVisitor extends RecursiveAstVisitor<void> {
  _FirebaseFunctionsVisitor(
    Map<String, InstanceCreationExpression>? sharedOptionsVars, {
    InstanceCreationExpression? globalOptions,
  }) : _globalOptionsExpr = globalOptions {
    if (sharedOptionsVars != null) {
      _variableToOptionsExpr.addAll(sharedOptionsVars);
    }
    namespaces = <_Namespace>[
      _Namespace(
        _extractHttpsFunction,
        '$_pkg/src/https/https_namespace.dart#HttpsNamespace',
        ['onRequest', 'onCall', 'onCallWithData'],
      ),
      _Namespace(
        _extractPubSubFunction,
        '$_pkg/src/pubsub/pubsub_namespace.dart#PubSubNamespace',
        ['onMessagePublished'],
      ),
      _Namespace(
        _extractFirestoreFunction,
        '$_pkg/src/firestore/firestore_namespace.dart#FirestoreNamespace',
        [
          'onDocumentCreated',
          'onDocumentUpdated',
          'onDocumentDeleted',
          'onDocumentWritten',
          'onDocumentCreatedWithAuthContext',
          'onDocumentUpdatedWithAuthContext',
          'onDocumentDeletedWithAuthContext',
          'onDocumentWrittenWithAuthContext',
        ],
      ),
      _Namespace(
        _extractDatabaseFunction,
        '$_pkg/src/database/database_namespace.dart#DatabaseNamespace',
        [
          'onValueCreated',
          'onValueUpdated',
          'onValueDeleted',
          'onValueWritten',
        ],
      ),
      _Namespace(
        _extractGenericAlertFunction,
        '$_pkg/src/alerts/alerts_namespace.dart#AlertsNamespace',
        ['onAlertPublished'],
      ),
      _Namespace(
        _extractCrashlyticsAlertFunction,
        '$_pkg/src/alerts/crashlytics_namespace.dart#CrashlyticsNamespace',
        [
          'onNewFatalIssuePublished',
          'onNewNonfatalIssuePublished',
          'onRegressionAlertPublished',
          'onStabilityDigestPublished',
          'onVelocityAlertPublished',
          'onNewAnrIssuePublished',
        ],
      ),
      _Namespace(
        _extractBillingAlertFunction,
        '$_pkg/src/alerts/billing_namespace.dart#BillingNamespace',
        ['onPlanUpdatePublished', 'onPlanAutomatedUpdatePublished'],
      ),
      _Namespace(
        _extractAppDistributionAlertFunction,
        '$_pkg/src/alerts/app_distribution_namespace.dart#AppDistributionNamespace',
        ['onNewTesterIosDevicePublished', 'onInAppFeedbackPublished'],
      ),
      _Namespace(
        _extractPerformanceAlertFunction,
        '$_pkg/src/alerts/performance_namespace.dart#PerformanceNamespace',
        ['onThresholdAlertPublished'],
      ),
      _Namespace(
        _extractIdentityFunction,
        '$_pkg/src/identity/identity_namespace.dart#IdentityNamespace',
        [
          'beforeUserCreated',
          'beforeUserSignedIn',
          'beforeEmailSent',
          'beforeSmsSent',
        ],
      ),
      _Namespace(
        _extractRemoteConfigFunction,
        '$_pkg/src/remote_config/remote_config_namespace.dart#RemoteConfigNamespace',
        ['onConfigUpdated'],
      ),
      _Namespace(
        _extractStorageFunction,
        '$_pkg/src/storage/storage_namespace.dart#StorageNamespace',
        [
          'onObjectArchived',
          'onObjectFinalized',
          'onObjectDeleted',
          'onObjectMetadataUpdated',
        ],
      ),
      _Namespace(
        // Adapter: _extractSchedulerFunction only takes node, not the second String arg
        (node, _) => _extractSchedulerFunction(node),
        '$_pkg/src/scheduler/scheduler_namespace.dart#SchedulerNamespace',
        ['onSchedule'],
      ),
      _Namespace(
        _extractTaskQueueFunction,
        '$_pkg/src/tasks/tasks_namespace.dart#TasksNamespace',
        ['onTaskDispatched'],
      ),
      _Namespace(
        _extractEventarcFunction,
        '$_pkg/src/eventarc/eventarc_namespace.dart#EventarcNamespace',
        ['onCustomEventPublished'],
      ),
      _Namespace(
        _extractTestLabFunction,
        '$_pkg/src/test_lab/test_lab_namespace.dart#TestLabNamespace',
        ['onTestMatrixCompleted'],
      ),
    ];
  }

  final Map<String, ParamSpec> params = {};
  final Map<String, EndpointSpec> endpoints = {};
  late final List<_Namespace> namespaces;
  final InstanceCreationExpression? _globalOptionsExpr;

  /// Maps variable names to their actual parameter names.
  /// e.g., 'minInstances' -> 'MIN_INSTANCES'
  final Map<String, String> _variableToParamName = {};

  /// Maps variable names to their InstanceCreationExpression initializers.
  /// Used to resolve options passed via variable references, e.g.:
  ///   const opts = HttpsOptions(region: Region(SupportedRegion.europeWest3));
  ///   firebase.https.onRequest(name: 'fn', options: opts, ...);
  final Map<String, InstanceCreationExpression> _variableToOptionsExpr = {};

  /// Top-level function declarations, used to follow helpers that are invoked
  /// from the `runFunctions`/`fireUp` registration callback.
  final Map<String, FunctionDeclaration> _topLevelFunctions = {};

  final Set<String> _visitedRegistrationHelpers = {};

  var _registrationDepth = 0;

  bool get _isCollectingRegistrations => _registrationDepth > 0;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    final methodName = node.methodName.name;

    if (target == null && _isFunctionsRunnerInvocation(methodName)) {
      _visitRegistrationRunner(node);
      return;
    }

    if (_isCollectingRegistrations && target != null) {
      // Check against all namespaces
      for (final namespace in namespaces) {
        if (namespace.isNamespace(target)) {
          if (namespace.matches(methodName)) {
            namespace.extractor(node, methodName);
            // The function handler runs later, so don't scan its body as if it
            // were part of initialization.
            return;
          }
        }
      }
    } else if (target == null) {
      // Check for parameter definitions (top-level function calls with no target)
      if (_isParamDefinition(methodName)) {
        _extractParameterFromMethod(node, methodName);
      } else if (_isCollectingRegistrations) {
        _visitRegistrationHelper(methodName);
      }
    }

    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    if (node.function case final SimpleIdentifier function) {
      final functionName = function.name;

      if (_isFunctionsRunnerInvocation(functionName)) {
        _visitRegistrationRunnerArguments(functionName, node.argumentList);
        return;
      }

      // Check for parameter definitions
      if (_isParamDefinition(functionName)) {
        _extractParameter(node, functionName);
      }
    }

    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitCompilationUnit(CompilationUnit node) {
    // Pre-pass: collect all top-level variable declarations so they're
    // available when resolving variable references in function declarations,
    // regardless of declaration order in the source file.
    for (final declaration in node.declarations) {
      if (declaration is TopLevelVariableDeclaration) {
        _trackOptionsVariables(declaration.variables);
      } else if (declaration is FunctionDeclaration) {
        _topLevelFunctions[declaration.name.lexeme] = declaration;
      }
    }
    super.visitCompilationUnit(node);
  }

  bool _isFunctionsRunnerInvocation(String methodName) =>
      methodName == 'runFunctions' || methodName == 'fireUp';

  void _visitRegistrationRunner(MethodInvocation node) {
    _visitRegistrationRunnerArguments(node.methodName.name, node.argumentList);
  }

  void _visitRegistrationRunnerArguments(String runnerName, ArgumentList args) {
    final arguments = args.arguments;
    final runnerArgIndex = runnerName == 'fireUp' ? 1 : 0;
    if (arguments.length <= runnerArgIndex) return;

    _visitRegistrationExpression(arguments[runnerArgIndex]);
  }

  void _visitRegistrationExpression(Expression expression) {
    switch (expression) {
      case FunctionExpression(:final body):
        _visitCollectingRegistrations(() => body.accept(this));
      case SimpleIdentifier(:final name):
        _visitRegistrationHelper(name);
      case ParenthesizedExpression(:final expression):
        _visitRegistrationExpression(expression);
    }
  }

  void _visitRegistrationHelper(String name) {
    if (!_visitedRegistrationHelpers.add(name)) return;

    final declaration = _topLevelFunctions[name];
    if (declaration == null) return;

    _visitCollectingRegistrations(() {
      declaration.functionExpression.body.accept(this);
    });
  }

  void _visitCollectingRegistrations(void Function() visit) {
    _registrationDepth++;
    try {
      visit();
    } finally {
      _registrationDepth--;
    }
  }

  @override
  void visitVariableDeclarationStatement(VariableDeclarationStatement node) {
    // Track local variable declarations (e.g., `const opts = HttpsOptions(...)`
    // inside a function body).
    _trackOptionsVariables(node.variables);
    super.visitVariableDeclarationStatement(node);
  }

  /// Tracks variables whose initializers are [InstanceCreationExpression]s,
  /// so they can be resolved when passed as options via variable reference.
  void _trackOptionsVariables(VariableDeclarationList variables) {
    for (final variable in variables.variables) {
      final initializer = variable.initializer;
      if (initializer is InstanceCreationExpression) {
        _variableToOptionsExpr[variable.name.lexeme] = initializer;
      }
    }
  }

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    // Track variable declarations for param definitions
    for (final variable in node.variables.variables) {
      final initializer = variable.initializer;

      // Handle top-level function calls like defineInt(...), defineString(...)
      // These can be either FunctionExpressionInvocation or MethodInvocation
      String? functionName;
      ArgumentList? argList;

      if (initializer is FunctionExpressionInvocation) {
        final function = initializer.function;
        if (function is SimpleIdentifier) {
          functionName = function.name;
          argList = initializer.argumentList;
        }
      } else if (initializer is MethodInvocation &&
          initializer.target == null) {
        // Top-level function call (no target)
        functionName = initializer.methodName.name;
        argList = initializer.argumentList;
      }

      if (functionName != null &&
          argList != null &&
          _isParamDefinition(functionName)) {
        // Extract the param name from the first argument
        final args = argList.arguments;
        if (args.isNotEmpty) {
          // Handle defineEnumList differently - it derives name from enum type
          if (functionName == 'defineEnumList') {
            final valuesArg = args.first;
            String? paramName;
            if (valuesArg is PrefixedIdentifier) {
              final enumTypeName = valuesArg.prefix.name;
              paramName = '${toUpperSnakeCase(enumTypeName)}_LIST';
            } else if (valuesArg is PropertyAccess) {
              final target = valuesArg.target;
              if (target is SimpleIdentifier) {
                paramName = '${toUpperSnakeCase(target.name)}_LIST';
              }
            }
            if (paramName != null) {
              _variableToParamName[variable.name.lexeme] = paramName;
            }
          } else {
            final nameArg = args.first;
            final paramName = _extractStringLiteral(nameArg);
            if (paramName != null) {
              // Map variable name to actual param name
              _variableToParamName[variable.name.lexeme] = paramName;
            }
          }
        }
      }
    }
    super.visitTopLevelVariableDeclaration(node);
  }

  /// Checks if this is a parameter definition function.
  bool _isParamDefinition(String name) =>
      name == 'defineString' ||
      name == 'defineInt' ||
      name == 'defineDouble' ||
      name == 'defineFloat' ||
      name == 'defineBoolean' ||
      name == 'defineList' ||
      name == 'defineEnumList' ||
      name == 'defineSecret' ||
      name == 'defineJsonSecret';

  /// Extracts an HTTPS function declaration.
  void _extractHttpsFunction(MethodInvocation node, String methodName) {
    // Extract function name from named argument

    final functionName = node.extractLiteralForArg('name');
    if (functionName == null) return;

    // Determine trigger type
    final triggerType = methodName == 'onRequest' ? 'https' : 'callable';

    endpoints[functionName] = EndpointSpec(
      name: functionName,
      type: triggerType,
      globalOptions: _globalOptionsExpr,
      options: node.findOptionsArg(_variableToOptionsExpr),
      variableToParamName: _variableToParamName,
    );
  }

  /// Extracts a Pub/Sub function declaration.
  void _extractPubSubFunction(MethodInvocation node, String methodName) {
    // Extract topic name from named argument
    final topicName = node.extractLiteralForArg('topic');
    if (topicName == null) return;

    // Generate function name from topic (remove hyphens to match Node.js behavior)
    final sanitizedTopic = topicName.replaceAll('-', '');
    final functionName = 'onMessagePublished_$sanitizedTopic';

    endpoints[functionName] = EndpointSpec(
      name: functionName,
      type: 'pubsub',
      topic: topicName, // Keep original topic name for eventFilters
      globalOptions: _globalOptionsExpr,
      options: node.findOptionsArg(_variableToOptionsExpr),
      variableToParamName: _variableToParamName,
    );
  }

  /// Extracts a Firestore function declaration.
  void _extractFirestoreFunction(MethodInvocation node, String methodName) {
    // Extract document path from named argument
    final documentPath = node.extractLiteralForArg('document');
    if (documentPath == null) return;

    // Extract options if present (for database and namespace)
    final optionsArg = node.findOptionsArg(_variableToOptionsExpr);
    String? database;
    String? namespace;

    if (optionsArg != null) {
      database = _extractStringField(optionsArg, 'database');
      namespace = _extractStringField(optionsArg, 'namespace');
    }

    // Generate function name from document path and event type
    // Similar to how we do it in firestore_namespace.dart
    final sanitizedPath = documentPath
        .replaceAll('/', '_')
        .replaceAll('{', '')
        .replaceAll('}', '')
        .replaceAll('-', '');
    final functionName = '${methodName}_$sanitizedPath';

    endpoints[functionName] = EndpointSpec(
      name: functionName,
      type: 'firestore',
      firestoreEventType: methodName,
      documentPath: documentPath,
      database: database ?? '(default)',
      namespace: namespace ?? '(default)',
      globalOptions: _globalOptionsExpr,
      options: optionsArg,
      variableToParamName: _variableToParamName,
    );
  }

  /// Extracts a Database function declaration.
  void _extractDatabaseFunction(MethodInvocation node, String methodName) {
    // Extract ref path from named argument
    final refPath = node.extractLiteralForArg('ref');
    if (refPath == null) return;

    // Extract options if present (for instance)
    final optionsArg = node.findOptionsArg(_variableToOptionsExpr);
    String? instance;

    if (optionsArg != null) {
      instance = _extractStringField(optionsArg, 'instance');
    }

    // Generate function name from ref path and event type
    // Similar to how we do it in database_namespace.dart
    final sanitizedPath = refPath
        .replaceAll(RegExp(r'^/+|/+$'), '') // Remove leading/trailing slashes
        .replaceAll('/', '_')
        .replaceAll('{', '')
        .replaceAll('}', '')
        .replaceAll('-', '');
    final functionName = '${methodName}_$sanitizedPath';

    endpoints[functionName] = EndpointSpec(
      name: functionName,
      type: 'database',
      databaseEventType: methodName,
      refPath: refPath,
      instance: instance ?? '*',
      globalOptions: _globalOptionsExpr,
      options: optionsArg,
      variableToParamName: _variableToParamName,
    );
  }

  /// Extracts a generic alert function declaration (onAlertPublished).
  void _extractGenericAlertFunction(MethodInvocation node, String methodName) {
    // Extract alertType from named argument

    final alertTypeValue = _extractAlertTypeValue(
      node.findNamedArg('alertType'),
    );
    if (alertTypeValue == null) return;

    // Extract appId from options if present
    final optionsArg = node.findOptionsArg(_variableToOptionsExpr);
    String? appId;

    if (optionsArg != null) {
      appId = _extractStringField(optionsArg, 'appId');
    }

    // Generate function name
    final sanitizedAlertType = alertTypeValue
        .replaceAll('.', '_')
        .replaceAll('-', '');
    final functionName = 'onAlertPublished_$sanitizedAlertType';

    endpoints[functionName] = EndpointSpec(
      name: functionName,
      type: 'alert',
      alertType: alertTypeValue,
      appId: appId,
      globalOptions: _globalOptionsExpr,
      options: optionsArg,
      variableToParamName: _variableToParamName,
    );
  }

  /// Extracts Crashlytics alert function declarations.
  void _extractCrashlyticsAlertFunction(
    MethodInvocation node,
    String methodName,
  ) {
    // Map method names to alert types
    final alertType = switch (methodName) {
      'onNewFatalIssuePublished' => 'crashlytics.newFatalIssue',
      'onNewNonfatalIssuePublished' => 'crashlytics.newNonfatalIssue',
      'onRegressionAlertPublished' => 'crashlytics.regression',
      'onStabilityDigestPublished' => 'crashlytics.stabilityDigest',
      'onVelocityAlertPublished' => 'crashlytics.velocity',
      'onNewAnrIssuePublished' => 'crashlytics.newAnrIssue',
      _ => null,
    };

    if (alertType == null) return;

    _extractAlertEndpoint(node, alertType);
  }

  /// Extracts Billing alert function declarations.
  void _extractBillingAlertFunction(MethodInvocation node, String methodName) {
    final alertType = switch (methodName) {
      'onPlanUpdatePublished' => 'billing.planUpdate',
      'onPlanAutomatedUpdatePublished' => 'billing.planAutomatedUpdate',
      _ => null,
    };

    if (alertType == null) return;

    _extractAlertEndpoint(node, alertType);
  }

  /// Extracts App Distribution alert function declarations.
  void _extractAppDistributionAlertFunction(
    MethodInvocation node,
    String methodName,
  ) {
    final alertType = switch (methodName) {
      'onNewTesterIosDevicePublished' => 'appDistribution.newTesterIosDevice',
      'onInAppFeedbackPublished' => 'appDistribution.inAppFeedback',
      _ => null,
    };

    if (alertType == null) return;

    _extractAlertEndpoint(node, alertType);
  }

  /// Extracts Performance alert function declarations.
  void _extractPerformanceAlertFunction(
    MethodInvocation node,
    String methodName,
  ) {
    final alertType = switch (methodName) {
      'onThresholdAlertPublished' => 'performance.threshold',
      _ => null,
    };

    if (alertType == null) return;

    _extractAlertEndpoint(node, alertType);
  }

  /// Extracts a Remote Config function declaration.
  void _extractRemoteConfigFunction(MethodInvocation node, String methodName) {
    // Remote Config has a single event type and no filters,
    // so the function name is always 'onConfigUpdated'.
    const functionName = 'onConfigUpdated';

    endpoints[functionName] = EndpointSpec(
      name: functionName,
      type: 'remoteConfig',
      globalOptions: _globalOptionsExpr,
      options: node.findOptionsArg(_variableToOptionsExpr),
      variableToParamName: _variableToParamName,
    );
  }

  /// Extracts a Storage function declaration.
  void _extractStorageFunction(MethodInvocation node, String methodName) {
    // Extract bucket name from named argument
    final bucketName = node.extractLiteralForArg('bucket');
    if (bucketName == null) return;

    // Generate function name from bucket (strip non-alphanumeric chars for valid function ID)
    final sanitizedBucket = bucketName.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
    final functionName = '${methodName}_$sanitizedBucket';

    endpoints[functionName] = EndpointSpec(
      name: functionName,
      type: 'storage',
      storageBucket: bucketName,
      storageEventType: methodName,
      globalOptions: _globalOptionsExpr,
      options: node.findOptionsArg(_variableToOptionsExpr),
      variableToParamName: _variableToParamName,
    );
  }

  /// Helper to extract alert endpoint from a method invocation.
  void _extractAlertEndpoint(MethodInvocation node, String alertType) {
    // Extract appId from options if present
    final optionsArg = node.findOptionsArg(_variableToOptionsExpr);
    String? appId;

    if (optionsArg != null) {
      appId = _extractStringField(optionsArg, 'appId');
    }

    // Generate function name
    final sanitizedAlertType = alertType
        .replaceAll('.', '_')
        .replaceAll('-', '');
    final functionName = 'onAlertPublished_$sanitizedAlertType';

    endpoints[functionName] = EndpointSpec(
      name: functionName,
      type: 'alert',
      alertType: alertType,
      appId: appId,
      globalOptions: _globalOptionsExpr,
      options: optionsArg,
      variableToParamName: _variableToParamName,
    );
  }

  /// Extracts an Identity function declaration.
  void _extractIdentityFunction(MethodInvocation node, String methodName) {
    // Map method names to event types
    final eventType = switch (methodName) {
      'beforeUserCreated' => 'beforeCreate',
      'beforeUserSignedIn' => 'beforeSignIn',
      'beforeEmailSent' => 'beforeSendEmail',
      'beforeSmsSent' => 'beforeSendSms',
      _ => null,
    };

    if (eventType == null) return;

    // Extract options if present
    final optionsArg = node.findOptionsArg(_variableToOptionsExpr);
    bool? idToken;
    bool? accessToken;
    bool? refreshToken;

    if (optionsArg != null) {
      idToken = _extractBoolField(optionsArg, 'idToken');
      accessToken = _extractBoolField(optionsArg, 'accessToken');
      refreshToken = _extractBoolField(optionsArg, 'refreshToken');
    }

    // Function name is the event type
    final functionName = eventType;

    endpoints[functionName] = EndpointSpec(
      name: functionName,
      type: 'blocking',
      blockingEventType: eventType,
      idToken: idToken,
      accessToken: accessToken,
      refreshToken: refreshToken,
      globalOptions: _globalOptionsExpr,
      options: optionsArg,
      variableToParamName: _variableToParamName,
    );
  }

  /// Extracts a Scheduler function declaration.
  void _extractSchedulerFunction(MethodInvocation node) {
    // Extract schedule from named argument
    final scheduleArg = node.findNamedArg('schedule');
    if (scheduleArg == null) return;

    final schedule = _extractStringLiteral(scheduleArg);
    if (schedule == null) return;

    // Generate function name from schedule (matching runtime behavior)
    final sanitized = schedule
        .replaceAll(' ', '_')
        .replaceAll('*', '')
        .replaceAll('/', '')
        .replaceAll('-', '')
        .replaceAll(',', '');
    final functionName = 'onSchedule_$sanitized';

    // Extract options if present
    final optionsArg = node.findOptionsArg(_variableToOptionsExpr);
    String? timeZone;
    Map<String, dynamic>? retryConfig;

    if (optionsArg != null) {
      timeZone = _extractSchedulerTimeZone(optionsArg);
      retryConfig = _extractRetryConfig(optionsArg);
    }

    endpoints[functionName] = EndpointSpec(
      name: functionName,
      type: 'scheduler',
      schedule: schedule,
      timeZone: timeZone,
      retryConfig: retryConfig,
      globalOptions: _globalOptionsExpr,
      options: optionsArg,
      variableToParamName: _variableToParamName,
    );
  }

  /// Extracts a Task Queue function declaration.
  void _extractTaskQueueFunction(MethodInvocation node, String methodName) {
    // Extract function name from named argument
    final functionName = node.extractLiteralForArg('name');
    if (functionName == null) return;

    // Extract options if present
    final optionsArg = node.findOptionsArg(_variableToOptionsExpr);
    Map<String, dynamic>? retryConfig;
    Map<String, dynamic>? rateLimits;

    if (optionsArg != null) {
      retryConfig = _extractTaskQueueRetryConfig(optionsArg);
      rateLimits = _extractTaskQueueRateLimits(optionsArg);
    }

    endpoints[functionName] = EndpointSpec(
      name: functionName,
      type: 'taskQueue',
      taskQueueRetryConfig: retryConfig,
      taskQueueRateLimits: rateLimits,
      globalOptions: _globalOptionsExpr,
      options: optionsArg,
      variableToParamName: _variableToParamName,
    );
  }

  /// Extracts an Eventarc function declaration.
  void _extractEventarcFunction(MethodInvocation node, String methodName) {
    // Extract eventType from named argument
    final eventType = node.extractLiteralForArg('eventType');
    if (eventType == null) return;

    // Generate function name from event type (remove non-alphanumeric chars)
    final sanitizedType = eventType.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
    final functionName = 'onCustomEventPublished_$sanitizedType';

    // Extract options if present (for channel and filters)
    final optionsArg = node.findOptionsArg(_variableToOptionsExpr);
    String? channel;
    Map<String, String>? filters;

    if (optionsArg != null) {
      channel = _extractStringField(optionsArg, 'channel');
      filters = _extractStringMapField(optionsArg, 'filters');
    }

    endpoints[functionName] = EndpointSpec(
      name: functionName,
      type: 'eventarc',
      eventarcEventType: eventType,
      eventarcChannel: channel ?? 'locations/us-central1/channels/firebase',
      eventarcFilters: filters,
      globalOptions: _globalOptionsExpr,
      options: optionsArg,
      variableToParamName: _variableToParamName,
    );
  }

  /// Extracts a Test Lab function declaration.
  void _extractTestLabFunction(MethodInvocation node, String methodName) {
    // Test Lab has a single event type and no filters,
    // so the function name is always 'onTestMatrixCompleted'.
    const functionName = 'onTestMatrixCompleted';

    endpoints[functionName] = EndpointSpec(
      name: functionName,
      type: 'testLab',
      globalOptions: _globalOptionsExpr,
      options: node.findOptionsArg(_variableToOptionsExpr),
      variableToParamName: _variableToParamName,
    );
  }

  /// Extracts a `Map<String, String>` field from an [InstanceCreationExpression].
  Map<String, String>? _extractStringMapField(
    InstanceCreationExpression node,
    String fieldName,
  ) {
    final arg = node.argumentList.arguments
        .whereType<NamedExpression>()
        .where((e) => e.name.label.name == fieldName)
        .map((e) => e.expression)
        .firstOrNull;

    if (arg is! SetOrMapLiteral || !arg.isMap) return null;

    final map = <String, String>{};
    for (final element in arg.elements) {
      if (element is MapLiteralEntry) {
        final key = element.key;
        final value = element.value;
        if (key is StringLiteral && value is StringLiteral) {
          map[key.stringValue!] = value.stringValue!;
        }
      }
    }

    return map.isEmpty ? null : map;
  }

  /// Extracts TaskQueueRetryConfig from TaskQueueOptions.
  Map<String, dynamic>? _extractTaskQueueRetryConfig(
    InstanceCreationExpression node,
  ) {
    final retryConfigArg = node.argumentList.arguments
        .whereType<NamedExpression>()
        .where((e) => e.name.label.name == 'retryConfig')
        .map((e) => e.expression)
        .firstOrNull;

    if (retryConfigArg is! InstanceCreationExpression) return null;

    final config = <String, dynamic>{};

    for (final arg in retryConfigArg.argumentList.arguments) {
      if (arg is! NamedExpression) continue;

      final fieldName = arg.name.label.name;
      final value = _extractRetryConfigValue(arg.expression);
      if (value != null) {
        config[fieldName] = value;
      }
    }

    return config.isEmpty ? null : config;
  }

  /// Extracts TaskQueueRateLimits from TaskQueueOptions.
  Map<String, dynamic>? _extractTaskQueueRateLimits(
    InstanceCreationExpression node,
  ) {
    final rateLimitsArg = node.argumentList.arguments
        .whereType<NamedExpression>()
        .where((e) => e.name.label.name == 'rateLimits')
        .map((e) => e.expression)
        .firstOrNull;

    if (rateLimitsArg is! InstanceCreationExpression) return null;

    final config = <String, dynamic>{};

    for (final arg in rateLimitsArg.argumentList.arguments) {
      if (arg is! NamedExpression) continue;

      final fieldName = arg.name.label.name;
      final value = _extractRetryConfigValue(arg.expression);
      if (value != null) {
        config[fieldName] = value;
      }
    }

    return config.isEmpty ? null : config;
  }

  /// Extracts timeZone from ScheduleOptions.
  String? _extractSchedulerTimeZone(InstanceCreationExpression node) {
    final timeZoneArg = node.argumentList.arguments
        .whereType<NamedExpression>()
        .where((e) => e.name.label.name == 'timeZone')
        .map((e) => e.expression)
        .firstOrNull;

    if (timeZoneArg is InstanceCreationExpression) {
      // TimeZone('America/New_York')
      final args = timeZoneArg.argumentList.arguments;
      if (args.firstOrNull case final StringLiteral firstArg) {
        return firstArg.stringValue;
      }
    }
    return null;
  }

  /// Extracts RetryConfig from ScheduleOptions.
  Map<String, dynamic>? _extractRetryConfig(InstanceCreationExpression node) {
    final retryConfigArg = node.argumentList.arguments
        .whereType<NamedExpression>()
        .where((e) => e.name.label.name == 'retryConfig')
        .map((e) => e.expression)
        .firstOrNull;

    if (retryConfigArg is! InstanceCreationExpression) return null;

    final config = <String, dynamic>{};

    for (final arg in retryConfigArg.argumentList.arguments) {
      if (arg is! NamedExpression) continue;

      final fieldName = arg.name.label.name;
      final value = _extractRetryConfigValue(arg.expression);
      if (value != null) {
        config[fieldName] = value;
      }
    }

    return config.isEmpty ? null : config;
  }

  /// Extracts a value from a retry config option.
  dynamic _extractRetryConfigValue(Expression expression) {
    if (expression is InstanceCreationExpression) {
      final args = expression.argumentList.arguments;
      if (args.isNotEmpty) {
        final first = args.first;
        if (first is IntegerLiteral) return first.value;
        if (first is DoubleLiteral) return first.value;
      }
    }
    return null;
  }

  /// Extracts a boolean field from an InstanceCreationExpression.
  bool? _extractBoolField(InstanceCreationExpression node, String fieldName) {
    final arg = node.argumentList.arguments
        .whereType<NamedExpression>()
        .where((e) => e.name.label.name == fieldName)
        .map((e) => e.expression)
        .firstOrNull;

    if (arg is BooleanLiteral) {
      return arg.value;
    }
    return null;
  }

  /// Extracts alert type value from an expression.
  String? _extractAlertTypeValue(Expression? expression) {
    if (expression is InstanceCreationExpression) {
      // Extract from constructor: const CrashlyticsNewFatalIssue()
      final typeName = expression.constructorName.type.name.lexeme;
      return switch (typeName) {
        'CrashlyticsNewFatalIssue' => 'crashlytics.newFatalIssue',
        'CrashlyticsNewNonfatalIssue' => 'crashlytics.newNonfatalIssue',
        'CrashlyticsRegression' => 'crashlytics.regression',
        'CrashlyticsStabilityDigest' => 'crashlytics.stabilityDigest',
        'CrashlyticsVelocity' => 'crashlytics.velocity',
        'CrashlyticsNewAnrIssue' => 'crashlytics.newAnrIssue',
        'BillingPlanUpdate' => 'billing.planUpdate',
        'BillingPlanAutomatedUpdate' => 'billing.planAutomatedUpdate',
        'AppDistributionNewTesterIosDevice' =>
          'appDistribution.newTesterIosDevice',
        'AppDistributionInAppFeedback' => 'appDistribution.inAppFeedback',
        'PerformanceThreshold' => 'performance.threshold',
        _ => null,
      };
    }
    return null;
  }

  /// Extracts a parameter definition from FunctionExpressionInvocation.
  void _extractParameter(
    FunctionExpressionInvocation node,
    String functionName,
  ) {
    _extractParamFromArgs(node.argumentList.arguments, functionName);
  }

  /// Extracts a parameter definition from MethodInvocation.
  void _extractParameterFromMethod(MethodInvocation node, String functionName) {
    _extractParamFromArgs(node.argumentList.arguments, functionName);
  }

  /// Common logic for extracting parameter definitions from arguments.
  void _extractParamFromArgs(NodeList<Expression> args, String functionName) {
    if (args.isEmpty) return;

    String? paramName;
    ParamOptions? paramOptions;

    // Handle defineEnumList which has a different signature:
    // defineEnumList(EnumType.values, [ParamOptions])
    if (functionName == 'defineEnumList') {
      // First argument is the enum values (e.g., Region.values)
      final valuesArg = args.first;
      if (valuesArg is PrefixedIdentifier) {
        // Extract the enum type name from "EnumType.values"
        final enumTypeName = valuesArg.prefix.name;
        paramName = '${toUpperSnakeCase(enumTypeName)}_LIST';
      } else if (valuesArg is PropertyAccess) {
        // Handle qualified access like mypackage.Region.values
        final target = valuesArg.target;
        if (target is PrefixedIdentifier) {
          paramName = '${toUpperSnakeCase(target.identifier.name)}_LIST';
        } else if (target is SimpleIdentifier) {
          paramName = '${toUpperSnakeCase(target.name)}_LIST';
        }
      }

      // Second argument is optional ParamOptions
      if (args.length > 1 && args[1] is InstanceCreationExpression) {
        paramOptions = _extractParamOptions(
          args[1] as InstanceCreationExpression,
        );
      }
    } else {
      // Standard parameter definitions: defineXxx('NAME', [ParamOptions])
      final nameArg = args.first;
      paramName = _extractStringLiteral(nameArg);

      // Second argument is optional ParamOptions (not used for secrets)
      if (args.length > 1 && args[1] is InstanceCreationExpression) {
        paramOptions = _extractParamOptions(
          args[1] as InstanceCreationExpression,
        );
      }
    }

    if (paramName == null) return;

    final paramType = _getParamType(functionName);
    final isJsonSecret = _isJsonSecret(functionName);

    params[paramName] = ParamSpec(
      name: paramName,
      type: paramType,
      options: paramOptions,
      format: isJsonSecret ? 'json' : null,
    );
  }

  /// Gets the parameter type name for YAML.
  String _getParamType(String functionName) => switch (functionName) {
    'defineString' => 'string',
    'defineSecret' || 'defineJsonSecret' => 'secret',
    'defineInt' => 'int',
    'defineDouble' || 'defineFloat' => 'float',
    'defineBoolean' => 'boolean',
    'defineList' || 'defineEnumList' => 'list',
    _ => 'string',
  };

  /// Checks if the parameter is a JSON secret.
  bool _isJsonSecret(String functionName) => functionName == 'defineJsonSecret';

  /// Extracts ParamOptions from an InstanceCreationExpression.
  ParamOptions? _extractParamOptions(InstanceCreationExpression node) =>
      ParamOptions(
        defaultValue: _extractDefaultValue(node),
        label: _extractStringField(node, 'label'),
        description: _extractStringField(node, 'description'),
      );

  /// Extracts the defaultValue field.
  Object? _extractDefaultValue(InstanceCreationExpression node) {
    final defaultValueArg = node.argumentList.arguments
        .whereType<NamedExpression>()
        .where((e) => e.name.label.name == 'defaultValue')
        .map((e) => e.expression)
        .firstOrNull;

    if (defaultValueArg == null) return null;

    return _extractConstValue(defaultValueArg);
  }

  /// Extracts a string field from options.
  String? _extractStringField(
    InstanceCreationExpression node,
    String fieldName,
  ) {
    final arg = node.argumentList.arguments
        .whereType<NamedExpression>()
        .where((e) => e.name.label.name == fieldName)
        .map((e) => e.expression)
        .firstOrNull;

    return _extractStringLiteral(arg);
  }
}

extension on MethodInvocation {
  /// Finds a named argument in a method invocation.
  Expression? findNamedArg(String name) => argumentList.arguments
      .whereType<NamedExpression>()
      .where((e) => e.name.label.name == name)
      .map((e) => e.expression)
      .firstOrNull;

  String? extractLiteralForArg(String name) =>
      _extractStringLiteral(findNamedArg(name));

  InstanceCreationExpression? findOptionsArg([
    Map<String, InstanceCreationExpression> variableToOptionsExpr = const {},
  ]) {
    final options = findNamedArg('options');
    if (options is InstanceCreationExpression) return options;

    // Resolve variable references, e.g., `options: opts` where
    // `const opts = HttpsOptions(...)` was declared earlier.
    if (options is SimpleIdentifier) {
      final tracked = variableToOptionsExpr[options.name];
      if (tracked != null) return tracked;
    }

    return null;
  }
}

/// Extracts a string literal or constant value.
String? _extractStringLiteral(Expression? expression) {
  if (expression == null) return null;
  final value = _extractConstValue(expression);
  return value is String ? value : null;
}

/// Extracts a constant value from an expression.
Object? _extractConstValue(Expression expression) {
  final literal = switch (expression) {
    StringLiteral() => expression.stringValue,
    IntegerLiteral() => expression.value,
    DoubleLiteral() => expression.value,
    BooleanLiteral() => expression.value,
    ListLiteral() =>
      expression.elements
          .whereType<Expression>()
          .map(_extractConstValue)
          .whereType<Object>()
          .toList(),
    _ => null,
  };

  if (literal != null) return literal;

  // Try to evaluate as constant if it's an identifier or property access
  Element? element;
  if (expression is SimpleIdentifier) {
    element = expression.element;
  } else if (expression is PrefixedIdentifier) {
    element = expression.element;
  } else if (expression is PropertyAccess) {
    element = expression.propertyName.element;
  }

  if (element is PropertyAccessorElement) {
    element = element.variable;
  }

  if (element is VariableElement && element.isConst) {
    final constant = element.computeConstantValue();
    if (constant != null) {
      final reader = ConstantReader(constant);
      if (reader.isString) return reader.stringValue;
      if (reader.isInt) return reader.intValue;
      if (reader.isDouble) return reader.doubleValue;
      if (reader.isBool) return reader.boolValue;
    }
  }

  return null;
}
