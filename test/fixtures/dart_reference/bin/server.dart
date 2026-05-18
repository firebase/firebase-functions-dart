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

// ignore_for_file: experimental_member_use

import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';
import 'package:firebase_functions/firebase_functions.dart';
import 'shared_options.dart';

// =============================================================================
// Parameterized Configuration Examples
// =============================================================================

// Define parameters - these are read from environment variables at runtime
// and can be configured at deploy time via .env files or CLI prompts.
final welcomeMessage = defineString(
  'WELCOME_MESSAGE',
  const ParamOptions(
    defaultValue: 'Hello from Dart Functions!',
    label: 'Welcome Message',
    description: 'The greeting message returned by the helloWorld function',
  ),
);

final minInstances = defineInt(
  'MIN_INSTANCES',
  const ParamOptions(
    defaultValue: 0,
    label: 'Minimum Instances',
    description: 'Minimum number of instances to keep warm',
  ),
);

final isProduction = defineBoolean(
  'IS_PRODUCTION',
  const ParamOptions(
    defaultValue: false,
    description: 'Whether this is a production deployment',
  ),
);

void main(List<String> args) async {
  FirebaseApp.initializeApp();

  await runFunctions((firebase) {
    // ==========================================================================
    // HTTPS Callable Functions (onCall / onCallWithData)
    // ==========================================================================

    // Basic callable function - untyped data
    firebase.https.onCall(name: 'greet', (request, response) async {
      final data = request.data as Map<String, dynamic>?;
      final name = data?['name'] ?? 'World';
      return CallableResult({'message': 'Hello, $name!'});
    });

    // Callable function with typed data using fromJson
    firebase.https.onCallWithData<GreetRequest, GreetResponse>(
      name: 'greetTyped',
      fromJson: GreetRequest.fromJson,
      (request, response) async {
        return GreetResponse(message: 'Hello, ${request.data.name}!');
      },
    );

    // Callable function demonstrating error handling
    firebase.https.onCall(name: 'divide', (request, response) async {
      final data = request.data as Map<String, dynamic>?;
      final a = (data?['a'] as num?)?.toDouble();
      final b = (data?['b'] as num?)?.toDouble();

      if (a == null || b == null) {
        throw InvalidArgumentError('Both "a" and "b" are required');
      }

      if (b == 0) {
        throw FailedPreconditionError('Cannot divide by zero');
      }

      return CallableResult({'result': a / b});
    });

    firebase.https.onCall(name: 'signInWithCode', (request, response) async {
      final auth = firebase.adminApp.auth();
      final customToken = await auth.createCustomToken('test-uid');
      return CallableResult({'token': customToken});
    });

    // Callable function demonstrating auth data extraction
    firebase.https.onCall(name: 'getAuthInfo', (request, response) async {
      final auth = request.auth;

      if (auth == null) {
        // User is not authenticated
        return CallableResult({
          'authenticated': false,
          'message': 'No authentication provided',
        });
      }

      // User is authenticated - return auth info
      return CallableResult({
        'authenticated': true,
        'uid': auth.uid,
        'token': auth.token, // Decoded JWT claims (email, name, etc.)
        // Note: auth.rawToken contains the raw JWT string if needed
      });
    });

    // Callable function with streaming support
    firebase.https.onCall(
      name: 'countdown',
      options: const CallableOptions(
        heartBeatIntervalSeconds: HeartBeatIntervalSeconds(5),
      ),
      (request, response) async {
        final data = request.data as Map<String, dynamic>?;
        final start = (data?['start'] as num?)?.toInt() ?? 10;

        // Stream countdown if client supports it
        if (request.acceptsStreaming) {
          for (var i = start; i >= 0; i--) {
            await response.sendChunk({'count': i});
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }

        return CallableResult({'message': 'Countdown complete!'});
      },
    );

    // ==========================================================================
    // HTTPS onRequest Functions
    // ==========================================================================

    // HTTPS onRequest example - using parameterized configuration
    firebase.https.onRequest(
      name: 'helloWorld',
      // ignore: non_const_argument_for_const_parameter
      options: HttpsOptions(
        // Use parameters in options - evaluated at deploy time
        minInstances: DeployOption.param(minInstances),
      ),
      (request) async {
        // Access parameter value at runtime
        return Response.ok(welcomeMessage.value());
      },
    );

    // Conditional configuration based on boolean parameter
    firebase.https.onRequest(
      name: 'configuredEndpoint',
      // ignore: non_const_argument_for_const_parameter
      options: HttpsOptions(
        // Use thenElse for conditional configuration at deploy time
        // isProduction.thenElse(trueValue, falseValue) returns an expression
        memory: Memory.expression(isProduction.thenElse(2048, 512)),
      ),
      (request) async {
        // Access parameter value at runtime
        final env = isProduction.value() ? 'production' : 'development';
        return Response.ok('Running in $env mode');
      },
    );

    // Pub/Sub trigger example
    firebase.pubsub.onMessagePublished(topic: 'my-topic', (event) async {
      final message = event.data;
      print('Received Pub/Sub message:');
      print('  ID: ${message?.messageId}');
      print('  Published: ${message?.publishTime}');
      print('  Data: ${message?.textData}');
      print('  Attributes: ${message?.attributes}');
    });

    // Firestore trigger examples
    firebase.firestore.onDocumentCreated(document: 'users/{userId}', (
      event,
    ) async {
      final data = event.data?.data();
      print('Document created: users/${event.params['userId']}');
      print('  Name: ${data?['name']}');
      print('  Email: ${data?['email']}');
    });

    firebase.firestore.onDocumentUpdated(document: 'users/{userId}', (
      event,
    ) async {
      final before = event.data?.before?.data();
      final after = event.data?.after?.data();
      print('Document updated: users/${event.params['userId']}');
      print('  Before: $before');
      print('  After: $after');
    });

    firebase.firestore.onDocumentDeleted(document: 'users/{userId}', (
      event,
    ) async {
      final data = event.data?.data();
      print('Document deleted: users/${event.params['userId']}');
      print('  Final data: $data');
      print(
        '[onDocumentDeleted] hasData=${data != null}'
        ' name=${data?['name']}'
        ' email=${data?['email']}'
        ' finalMessage=${data?['finalMessage']}',
      );
    });

    firebase.firestore.onDocumentWritten(document: 'users/{userId}', (
      event,
    ) async {
      final before = event.data?.before?.data();
      final after = event.data?.after?.data();
      print('Document written: users/${event.params['userId']}');
      if (before == null && after != null) {
        print('  Operation: CREATE');
      } else if (before != null && after != null) {
        print('  Operation: UPDATE');
      } else if (before != null && after == null) {
        print('  Operation: DELETE');
      }
    });

    // Firestore WithAuthContext trigger examples
    firebase.firestore.onDocumentCreatedWithAuthContext(
      document: 'orders/{orderId}',
      (event) async {
        print('Document created by: ${event.authType} (${event.authId})');
        final data = event.data?.data();
        print('  Order: ${data?['product']}');
      },
    );

    firebase.firestore.onDocumentUpdatedWithAuthContext(
      document: 'orders/{orderId}',
      (event) async {
        print('Document updated by: ${event.authType} (${event.authId})');
      },
    );

    firebase.firestore.onDocumentDeletedWithAuthContext(
      document: 'orders/{orderId}',
      (event) async {
        print('Document deleted by: ${event.authType} (${event.authId})');
      },
    );

    firebase.firestore.onDocumentWrittenWithAuthContext(
      document: 'orders/{orderId}',
      (event) async {
        print('Document written by: ${event.authType} (${event.authId})');
      },
    );

    // Nested collection trigger example
    firebase.firestore.onDocumentCreated(
      document: 'posts/{postId}/comments/{commentId}',
      (event) async {
        final data = event.data?.data();
        print(
          'Comment created: posts/${event.params['postId']}/comments/${event.params['commentId']}',
        );
        print('  Text: ${data?['text']}');
        print('  Author: ${data?['author']}');
      },
    );

    // ==========================================================================
    // Realtime Database trigger examples
    // ==========================================================================

    // Database onValueCreated - triggers when data is created
    firebase.database.onValueCreated(ref: 'messages/{messageId}', (
      event,
    ) async {
      final data = event.data?.val();
      print('Database value created: messages/${event.params['messageId']}');
      print('  Data: $data');
      print('  Instance: ${event.instance}');
      print('  Ref: ${event.ref}');
    });

    // Database onValueUpdated - triggers when data is updated
    firebase.database.onValueUpdated(ref: 'messages/{messageId}', (
      event,
    ) async {
      final before = event.data?.before?.val();
      final after = event.data?.after?.val();
      print('Database value updated: messages/${event.params['messageId']}');
      print('  Before: $before');
      print('  After: $after');
    });

    // Database onValueDeleted - triggers when data is deleted
    firebase.database.onValueDeleted(ref: 'messages/{messageId}', (
      event,
    ) async {
      final data = event.data?.val();
      print('Database value deleted: messages/${event.params['messageId']}');
      print('  Final data: $data');
    });

    // Database onValueWritten - triggers on any write (create, update, delete)
    firebase.database.onValueWritten(ref: 'messages/{messageId}', (
      event,
    ) async {
      final before = event.data?.before;
      final after = event.data?.after;
      print('Database value written: messages/${event.params['messageId']}');
      if (before == null || !before.exists()) {
        print('  Operation: CREATE');
        print('  New data: ${after?.val()}');
      } else if (after == null || !after.exists()) {
        print('  Operation: DELETE');
        print('  Deleted data: ${before.val()}');
      } else {
        print('  Operation: UPDATE');
        print('  Before: ${before.val()}');
        print('  After: ${after.val()}');
      }
    });

    // Nested path database trigger
    firebase.database.onValueWritten(ref: 'users/{userId}/status', (
      event,
    ) async {
      final after = event.data?.after?.val();
      print('User status changed: ${event.params['userId']}');
      print('  New status: $after');
    });

    // ==========================================================================
    // Firebase Alerts trigger examples
    // ==========================================================================

    // Crashlytics new fatal issue alert
    firebase.alerts.crashlytics.onNewFatalIssuePublished((event) async {
      final issue = event.data?.payload.issue;
      print('New fatal issue in Crashlytics:');
      print('  Issue ID: ${issue?.id}');
      print('  Title: ${issue?.title}');
      print('  App Version: ${issue?.appVersion}');
      print('  App ID: ${event.appId}');
    });

    // Billing plan update alert
    firebase.alerts.billing.onPlanUpdatePublished((event) async {
      final payload = event.data?.payload;
      print('Billing plan updated:');
      print('  New Plan: ${payload?.billingPlan}');
      print('  Updated By: ${payload?.principalEmail}');
      print('  Type: ${payload?.notificationType}');
    });

    // Performance threshold alert with app ID filter
    firebase.alerts.performance.onThresholdAlertPublished(
      options: const AlertOptions(appId: '1:123456789:ios:abcdef'),
      (event) async {
        final payload = event.data?.payload;
        print('Performance threshold exceeded:');
        print('  Event: ${payload?.eventName}');
        print('  Metric: ${payload?.metricType}');
        print(
          '  Threshold: ${payload?.thresholdValue} ${payload?.thresholdUnit}',
        );
        print('  Actual: ${payload?.violationValue} ${payload?.violationUnit}');
      },
    );

    // ==========================================================================
    // Identity Platform (Auth Blocking) trigger examples
    // ==========================================================================

    // Before user created - runs before a new user is created
    firebase.identity.beforeUserCreated(
      options: const BlockingOptions(idToken: true, accessToken: true),
      (AuthBlockingEvent event) async {
        final user = event.data;
        print('Before user created:');
        print('  UID: ${user?.uid}');
        print('  Email: ${user?.email}');
        print('  Provider: ${event.additionalUserInfo?.providerId}');

        // Example: Block users with certain email domains
        final email = user?.email;
        if (email != null && email.endsWith('@blocked.com')) {
          throw PermissionDeniedError('Email domain not allowed');
        }

        // Example: Set custom claims based on email domain
        if (email != null && email.endsWith('@admin.com')) {
          return const BeforeCreateResponse(customClaims: {'admin': true});
        }

        return null;
      },
    );

    // Before user signed in - runs before a user signs in
    firebase.identity.beforeUserSignedIn(
      options: const BlockingOptions(idToken: true),
      (AuthBlockingEvent event) async {
        final user = event.data;
        print('Before user signed in:');
        print('  UID: ${user?.uid}');
        print('  Email: ${user?.email}');
        print('  IP Address: ${event.ipAddress}');

        // Example: Add session claims for tracking
        return BeforeSignInResponse(
          sessionClaims: {
            'lastLogin': DateTime.now().toIso8601String(),
            'signInIp': event.ipAddress,
          },
        );
      },
    );

    // Before email sent - runs before password reset or sign-in emails
    // NOTE: The Auth emulator only supports beforeCreate and beforeSignIn.
    // This function is included for manifest snapshot testing but cannot be
    // tested with the emulator.
    firebase.identity.beforeEmailSent((AuthBlockingEvent event) async {
      print('Before email sent:');
      print('  Email Type: ${event.emailType?.value}');
      print('  IP Address: ${event.ipAddress}');

      // Example: Rate limit password reset emails
      // In production, you'd check against a database
      if (event.emailType == EmailType.passwordReset) {
        // Could return BeforeEmailResponse(
        //   recaptchaActionOverride: RecaptchaActionOptions.block,
        // ) to block suspicious requests
      }

      return null;
    });

    // Before SMS sent - runs before MFA or sign-in SMS messages
    // NOTE: The Auth emulator only supports beforeCreate and beforeSignIn.
    // This function is included for manifest snapshot testing but cannot be
    // tested with the emulator.
    firebase.identity.beforeSmsSent((AuthBlockingEvent event) async {
      print('Before SMS sent:');
      print('  SMS Type: ${event.smsType?.value}');
      print('  Phone: ${event.additionalUserInfo?.phoneNumber}');

      // Example: Block SMS to certain country codes
      final phone = event.additionalUserInfo?.phoneNumber;
      if (phone != null && phone.startsWith('+1900')) {
        return const BeforeSmsResponse(
          recaptchaActionOverride: RecaptchaActionOptions.block,
        );
      }

      return null;
    });

    // ==========================================================================
    // Remote Config trigger examples
    // ==========================================================================

    // Remote Config update trigger
    firebase.remoteConfig.onConfigUpdated((event) async {
      final data = event.data;
      print('Remote Config updated:');
      print('  Version: ${data?.versionNumber}');
      print('  Description: ${data?.description}');
      print('  Update Origin: ${data?.updateOrigin.value}');
      print('  Update Type: ${data?.updateType.value}');
      print('  Updated By: ${data?.updateUser.email}');
    });

    // ==========================================================================
    // Cloud Storage trigger examples
    // ==========================================================================

    // Storage onObjectFinalized - triggers when an object is created/overwritten
    firebase.storage.onObjectFinalized(
      bucket: 'demo-test.firebasestorage.app',
      (event) async {
        final data = event.data;
        print('Object finalized in bucket: ${event.bucket}');
        print('  Name: ${data?.name}');
        print('  Content Type: ${data?.contentType}');
        print('  Size: ${data?.size}');
      },
    );

    // Storage onObjectArchived - triggers when an object is archived
    firebase.storage.onObjectArchived(bucket: 'demo-test.firebasestorage.app', (
      event,
    ) async {
      final data = event.data;
      print('Object archived in bucket: ${event.bucket}');
      print('  Name: ${data?.name}');
      print('  Storage Class: ${data?.storageClass}');
    });

    // Storage onObjectDeleted - triggers when an object is deleted
    firebase.storage.onObjectDeleted(bucket: 'demo-test.firebasestorage.app', (
      event,
    ) async {
      final data = event.data;
      print('Object deleted in bucket: ${event.bucket}');
      print('  Name: ${data?.name}');
    });

    // Storage onObjectMetadataUpdated - triggers when object metadata changes
    firebase.storage.onObjectMetadataUpdated(
      bucket: 'demo-test.firebasestorage.app',
      (event) async {
        final data = event.data;
        print('Object metadata updated in bucket: ${event.bucket}');
        print('  Name: ${data?.name}');
        print('  Metadata: ${data?.metadata}');
      },
    );

    // ==========================================================================
    // Eventarc trigger examples
    // ==========================================================================

    // Basic Eventarc custom event - uses default Firebase channel
    firebase.eventarc.onCustomEventPublished(eventType: 'com.example.myevent', (
      event,
    ) async {
      print('Received custom Eventarc event:');
      print('  Type: ${event.type}');
      print('  Source: ${event.source}');
      print('  Data: ${event.data}');
    });

    // Eventarc custom event with channel and filters
    firebase.eventarc.onCustomEventPublished(
      eventType: 'com.example.filtered',
      options: const EventarcTriggerOptions(
        channel: 'my-channel',
        filters: {'category': 'important'},
      ),
      (event) async {
        print('Received filtered Eventarc event:');
        print('  Type: ${event.type}');
        print('  Data: ${event.data}');
      },
    );

    // ==========================================================================
    // Scheduler trigger examples
    // ==========================================================================

    // Basic scheduled function - runs every day at midnight
    firebase.scheduler.onSchedule(schedule: '0 0 * * *', (event) async {
      print('Scheduled function triggered:');
      print('  Job Name: ${event.jobName}');
      print('  Schedule Time: ${event.scheduleTime}');
      // Perform daily cleanup, send reports, etc.
    });

    // Scheduled function with timezone and retry config
    firebase.scheduler.onSchedule(
      schedule: '0 9 * * 1-5',
      options: const ScheduleOptions(
        timeZone: TimeZone('America/New_York'),
        retryConfig: RetryConfig(
          retryCount: RetryCount(3),
          maxRetrySeconds: MaxRetrySeconds(60),
          minBackoffSeconds: MinBackoffSeconds(5),
          maxBackoffSeconds: MaxBackoffSeconds(30),
        ),
        memory: Memory(MemoryOption.mb256),
      ),
      (event) async {
        print('Weekday morning report:');
        print('  Executed at: ${event.scheduleDateTime}');
        // Generate and send morning reports
      },
    );

    // ==========================================================================
    // Test Lab trigger examples
    // ==========================================================================

    // Test Lab onTestMatrixCompleted - triggers when a test matrix completes
    firebase.testLab.onTestMatrixCompleted((event) async {
      final data = event.data;
      print('Test matrix completed:');
      print('  Matrix ID: ${data?.testMatrixId}');
      print('  State: ${data?.state.value}');
      print('  Outcome: ${data?.outcomeSummary.value}');
      print('  Client: ${data?.clientInfo.client}');
      print('  Results URI: ${data?.resultStorage.resultsUri}');
    });

    // ==========================================================================
    // Task Queue trigger examples
    // ==========================================================================

    // Basic task queue function
    firebase.tasks.onTaskDispatched(name: 'processOrder', (request) async {
      final data = request.data as Map<String, dynamic>;
      print('Processing order: ${data['orderId']}');
      print('Task ID: ${request.id}');
      print('Queue: ${request.queueName}');
      print('Retry count: ${request.retryCount}');
    });

    // Task queue function with options
    firebase.tasks.onTaskDispatched(
      name: 'sendEmail',
      options: const TaskQueueOptions(
        retryConfig: TaskQueueRetryConfig(
          maxAttempts: MaxAttempts(5),
          maxRetrySeconds: TaskMaxRetrySeconds(300),
          minBackoffSeconds: TaskMinBackoffSeconds(10),
          maxBackoffSeconds: TaskMaxBackoffSeconds(60),
          maxDoublings: TaskMaxDoublings(3),
        ),
        rateLimits: TaskQueueRateLimits(
          maxConcurrentDispatches: MaxConcurrentDispatches(100),
          maxDispatchesPerSecond: MaxDispatchesPerSecond(50),
        ),
        memory: Memory(MemoryOption.mb512),
      ),
      (request) async {
        final data = request.data as Map<String, dynamic>;
        print('Sending email to: ${data['to']}');
        print('Subject: ${data['subject']}');
      },
    );

    // ==========================================================================
    // Options Tests - functions with comprehensive option configurations
    // ==========================================================================

    // HTTPS onRequest with ALL GlobalOptions + cors
    firebase.https.onRequest(
      name: 'httpsFull',
      options: const HttpsOptions(
        // GlobalOptions (manifest options)
        memory: Memory(MemoryOption.mb512),
        cpu: Cpu(1),
        region: Region(SupportedRegion.usCentral1),
        timeoutSeconds: TimeoutSeconds(60),
        minInstances: Instances(0),
        maxInstances: Instances(10),
        concurrency: Concurrency(80),
        serviceAccount: ServiceAccount('test@example.com'),
        vpcConnector: VpcConnector(
          'projects/test/locations/us-central1/connectors/vpc',
        ),
        vpcConnectorEgressSettings: VpcConnectorEgressSettings(
          VpcEgressSetting.privateRangesOnly,
        ),
        ingressSettings: Ingress(IngressSetting.allowAll),
        invoker: Invoker.public(),
        labels: {'environment': 'test', 'team': 'backend'},
        omit: Omit(false),
        // Runtime-only options (NOT in manifest)
        preserveExternalChanges: PreserveExternalChanges(true),
        cors: Cors(['https://example.com', 'https://app.example.com']),
      ),
      (request) async => Response.ok('HTTPS with all options'),
    );

    // Callable with ALL CallableOptions
    firebase.https.onCall(
      name: 'callableFull',
      options: const CallableOptions(
        memory: Memory(MemoryOption.gb1),
        cpu: Cpu(2),
        region: Region(SupportedRegion.usEast1),
        timeoutSeconds: TimeoutSeconds(300),
        minInstances: Instances(1),
        maxInstances: Instances(100),
        concurrency: Concurrency(80),
        invoker: Invoker.private(),
        labels: {'type': 'callable'},
        // Runtime-only options (NOT in manifest)
        enforceAppCheck: EnforceAppCheck(true),
        consumeAppCheckToken: ConsumeAppCheckToken(true),
        heartBeatIntervalSeconds: HeartBeatIntervalSeconds(30),
        cors: Cors(['*']),
      ),
      (request, response) async {
        return CallableResult({'message': 'Callable with all options'});
      },
    );

    // HTTPS onRequest that crashes with sensitive data in the exception.
    // Used by E2E tests to verify errors are logged but NOT leaked to clients.
    firebase.https.onRequest(name: 'crashWithSecret', (request) async {
      throw StateError('Unexpected failure — sensitive data: SECRET_DATA');
    });

    // HTTPS onRequest that crashes from an unexpected runtime error.
    // Simulates a real bug (bad cast) to verify we don't leak internals.
    firebase.https.onRequest(name: 'crashUnexpected', (request) async {
      final data = {'count': 'not_a_number'};
      // This will throw a TypeError at runtime
      final count = data['count'] as int;
      return Response.ok('count=$count');
    });

    // GCF Gen1 CPU option
    firebase.https.onRequest(
      name: 'httpsGen1',
      options: const HttpsOptions(cpu: Cpu.gcfGen1()),
      (request) async => Response.ok('GCF Gen1 CPU'),
    );

    // Custom invoker list
    firebase.https.onRequest(
      name: _OptionsSilly.httpsCustomInvoker,
      options: const HttpsOptions(
        invoker: Invoker(['user1@example.com', 'user2@example.com']),
      ),
      (request) async => Response.ok('Custom invoker'),
    );

    // Pub/Sub with options
    firebase.pubsub.onMessagePublished(
      topic: optionsTopic,
      options: const PubSubOptions(
        memory: Memory(MemoryOption.mb256),
        timeoutSeconds: TimeoutSeconds(120),
        region: Region(SupportedRegion.usWest1),
      ),
      (event) async {
        print('Pub/Sub with options');
      },
    );

    // ==========================================================================
    // Options via variable reference
    // ==========================================================================

    // Options assigned to a top-level const variable
    firebase.https.onRequest(
      name: 'httpsVarOptions',
      options: httpsVarOpts,
      (request) async => Response.ok('Options via variable'),
    );

    // Options assigned to a local const variable
    const localOpts = HttpsOptions(
      region: Region(SupportedRegion.europeWest1),
      memory: Memory(MemoryOption.gb2),
    );
    firebase.https.onRequest(
      name: 'httpsLocalVarOptions',
      options: localOpts,
      (request) async => Response.ok('Options via local variable'),
    );

    // Options declared in a separate file — the builder can now resolve these
    // using the shared options map collected in the first pass.
    firebase.https.onRequest(
      name: 'httpsCrossFileOptions',
      options: crossFileOpts,
      (request) async => Response.ok('Cross-file options'),
    );

    print('Functions registered successfully!');
  });
}

/// Options assigned to a top-level const variable.
const httpsVarOpts = HttpsOptions(
  region: Region(SupportedRegion.europeWest3),
  memory: Memory(MemoryOption.gb1),
  timeoutSeconds: TimeoutSeconds(120),
);

/// Testing constant expression evaluation
const optionsTopic = 'options-topic';

class _OptionsSilly {
  /// Testing constant expression evaluation
  static const httpsCustomInvoker = 'httpsCustomInvoker';
}

// =============================================================================
// Data classes for typed callable functions
// =============================================================================

/// Request data for the greetTyped callable function.
class GreetRequest {
  GreetRequest({required this.name});

  factory GreetRequest.fromJson(Map<String, dynamic> json) {
    return GreetRequest(name: json['name'] as String? ?? 'World');
  }

  final String name;

  Map<String, dynamic> toJson() => {'name': name};
}

/// Response data for the greetTyped callable function.
class GreetResponse {
  GreetResponse({required this.message});

  final String message;

  Map<String, dynamic> toJson() => {'message': message};
}
