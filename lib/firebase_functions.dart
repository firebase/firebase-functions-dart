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

/// Firebase Functions for Dart
///
/// Write Firebase Cloud Functions in Dart with full type safety.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:firebase_functions/firebase_functions.dart';
///
/// void main(List<String> args) {
///   runFunctions((firebase) {
///     firebase.https.onRequest(
///       name: 'hello',
///       (request) async => Response.ok('Hello, World!'),
///     );
///   });
/// }
/// ```
///
/// ## Parameterized Configuration
///
/// Use parameters for deploy-time and runtime configuration:
///
/// ```dart
/// final welcomeMessage = defineString('WELCOME_MESSAGE',
///     ParamOptions(defaultValue: 'Hello!'));
///
/// firebase.https.onRequest(
///   name: 'greet',
///   (request) async => Response.ok(welcomeMessage.value()),
/// );
/// ```
///
/// ## Secrets
///
/// Store sensitive values in Cloud Secret Manager:
///
/// ```dart
/// final apiKey = defineSecret('API_KEY');
///
/// firebase.https.onRequest(
///   name: 'secure',
///   options: HttpsOptions(secrets: [apiKey]),
///   (request) async {
///     // apiKey.value() is only available at runtime
///     return Response.ok('Configured');
///   },
/// );
/// ```
///
/// ## Trigger Support
///
/// Only HTTPS triggers (`onRequest`, `onCall`, `onCallWithData`) are
/// production-ready. All other trigger types are marked `@experimental`:
///
/// - **Emulator only**: Firestore, Realtime Database, Storage
/// - **Not yet supported**: Pub/Sub, Alerts, Eventarc, Identity, Remote Config,
///   Scheduler, Tasks, Test Lab
///
/// See also:
/// - [params] for the full params API
/// - [onInit] for safe initialization with secrets
/// - Firebase Admin SDK initialization: if the default Admin SDK app already
///   exists when `runFunctions` starts, the runtime reuses it. Otherwise it
///   creates one automatically with Application Default Credentials. To use a
///   service account JSON file, initialize the default Admin SDK app with
///   `Credential.fromServiceAccount(...)` before calling `runFunctions`, or set
///   `GOOGLE_APPLICATION_CREDENTIALS` for Application Default Credentials.
///
/// @docImport 'src/common/on_init.dart';
library;

// Used for the `params` import in the docs!
import 'params.dart' as params;

// Package re-exports
export 'package:google_cloud_firestore/google_cloud_firestore.dart'
    show DocumentData, DocumentSnapshot, QueryDocumentSnapshot;
export 'package:shelf/shelf.dart' show Request, Response;

// Built-in params
export 'params.dart' show databaseURL, gcloudProject, projectID, storageBucket;
// Experimental: Alerts triggers (not yet supported in production or emulator)
export 'src/alerts/alerts.dart';
// Common types
export 'src/common/cloud_event.dart';
export 'src/common/expression.dart';
export 'src/common/on_init.dart' show onInit;
export 'src/common/options.dart';
export 'src/common/params.dart';
// Experimental: Realtime Database triggers (emulator only)
export 'src/database/database.dart';
// Experimental: Eventarc triggers (not yet supported in production or emulator)
export 'src/eventarc/eventarc.dart';
// Core firebase instance
export 'src/firebase.dart' show Firebase;
// Experimental: Firestore triggers (emulator only)
export 'src/firestore/firestore.dart';
// HTTPS triggers (production-ready)
export 'src/https/https.dart';
// Experimental: Identity triggers (not yet supported in production or emulator)
export 'src/identity/identity.dart';
// Experimental: Pub/Sub triggers (not yet supported in production or emulator)
export 'src/pubsub/pubsub.dart';
// Experimental: Remote Config triggers (not yet supported in production or emulator)
export 'src/remote_config/remote_config.dart';
// Experimental: Scheduler triggers (not yet supported in production or emulator)
export 'src/scheduler/scheduler.dart';
// Core runtime
export 'src/server.dart' show fireUp, runFunctions;
// Experimental: Storage triggers (emulator only)
export 'src/storage/storage.dart';
// Experimental: Task queue triggers (not yet supported in production or emulator)
export 'src/tasks/tasks.dart';
// Experimental: Test Lab triggers (not yet supported in production or emulator)
export 'src/test_lab/test_lab.dart';
