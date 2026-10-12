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

/// Firebase Functions parameter system.
///
/// Provides strongly-typed configuration that works at both deploy time
/// and runtime. Parameters can be defined using factory functions and
/// their values are read from environment variables.
///
/// ## Basic Usage
///
/// ```dart
/// import 'package:firebase_functions/params.dart';
///
/// // Define parameters
/// final welcomeMessage = defineString(
///   'WELCOME_MESSAGE',
///   ParamOptions(defaultValue: 'Hello!'),
/// );
///
/// final minInstances = defineInt(
///   'MIN_INSTANCES',
///   ParamOptions(defaultValue: 0),
/// );
///
/// // Use at runtime
/// firebase.https.onRequest(
///   name: 'greet',
///   (request) async {
///     return Response.ok(welcomeMessage.value());
///   },
/// );
/// ```
///
/// ## Secrets
///
/// For sensitive values, use secrets stored in Cloud Secret Manager:
///
/// ```dart
/// final apiKey = defineSecret('API_KEY');
///
/// firebase.https.onRequest(
///   name: 'secure',
///   options: HttpsOptions(secrets: [apiKey]),
///   (request) async {
///     final key = apiKey.value();
///     return Response.ok('Using API key');
///   },
/// );
/// ```
///
/// ## Built-in Parameters
///
/// Several parameters are built-in and always available:
///
/// - [projectID] - The Cloud project ID
/// - [databaseURL] - The Realtime Database URL (if configured)
/// - [storageBucket] - The Cloud Storage bucket (if configured)
/// - [gcloudProject] - Alias for projectID
///
/// ## Conditional Configuration
///
/// Use boolean parameters for conditional deployment configuration:
///
/// ```dart
/// final isProduction = defineBoolean('IS_PRODUCTION');
///
/// firebase.https.onRequest(
///   name: 'api',
///   options: HttpsOptions(
///     minInstances: isProduction.thenElse(2, 0),
///   ),
///   handler,
/// );
/// ```
///
/// @docImport 'params.dart';
library;

import 'src/common/params.dart' as internal;

// Re-export expression types
export 'src/common/expression.dart'
    show
        Equals,
        Expression,
        GreaterThan,
        GreaterThanOrEqualTo,
        If,
        LessThan,
        LessThanOrEqualTo,
        LiteralExpression,
        NotEquals;
// Re-export onInit
export 'src/common/on_init.dart' show onInit;
// Re-export factory functions
export 'src/common/params.dart'
    show
        BooleanParam,
        DoubleParam,
        EnumListParam,
        IntParam,
        InternalExpression,
        JsonSecretParam,
        ListParam,
        MultiSelectParamInput,
        Param,
        ParamInput,
        ParamOptions,
        ResourceInput,
        SecretParam,
        SelectOption,
        SelectParamInput,
        StringParam,
        TextParamInput,
        WireParamSpec,
        clearParams,
        declaredParams,
        defineBoolean,
        defineDouble,
        defineEnumList,
        defineFloat,
        defineInt,
        defineJsonSecret,
        defineList,
        defineSecret,
        defineString;

// ============================================================================
// Built-in Parameters
// ============================================================================

/// Built-in parameter that resolves to the Cloud project ID.
///
/// This parameter is always available and does not need to be defined.
/// The value is read from the `FIREBASE_CONFIG` environment variable.
///
/// Example:
/// ```dart
/// firebase.https.onRequest(
///   name: 'info',
///   (request) async {
///     return Response.ok('Project: ${projectID.value()}');
///   },
/// );
/// ```
const internal.Param<String> projectID = internal.ParamInput.projectId;

/// Built-in parameter that resolves to the Realtime Database URL.
///
/// Returns an empty string if Realtime Database is not configured for the project.
const internal.Param<String> databaseURL = internal.ParamInput.databaseURL;

/// Built-in parameter that resolves to the Cloud Storage bucket.
///
/// Returns an empty string if Cloud Storage is not configured for the project.
const internal.Param<String> storageBucket = internal.ParamInput.storageBucket;

/// Built-in parameter that resolves to the GCloud project ID.
///
/// This is an alias for [projectID] for compatibility.
const internal.Param<String> gcloudProject = internal.ParamInput.gcloudProject;

/// Resource input for selecting a Cloud Storage bucket.
///
/// Use this with [ParamInput.select] or as the `input` option for a string
/// parameter to let users select from available buckets at deploy time.
const bucketPicker = internal.ParamInput.bucketPicker;
