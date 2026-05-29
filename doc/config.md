# Parameters & Configuration

## Defining Parameters

```dart
final welcomeMessage = defineString(
  'WELCOME_MESSAGE',
  ParamOptions(
    defaultValue: 'Hello from Dart!',
    label: 'Welcome Message',
    description: 'The greeting message returned by the function',
  ),
);

final minInstances = defineInt(
  'MIN_INSTANCES',
  ParamOptions(defaultValue: 0),
);

final isProduction = defineBoolean(
  'IS_PRODUCTION',
  ParamOptions(defaultValue: false),
);
```

## Using Parameters at Runtime

```dart
firebase.https.onRequest(
  name: 'hello',
  (request) async {
    return Response.ok(welcomeMessage.value());
  },
);
```

## Using Parameters in Options (Deploy-time)

```dart
firebase.https.onRequest(
  name: 'configured',
  options: HttpsOptions(
    minInstances: DeployOption.param(minInstances),
  ),
  handler,
);
```

## Conditional Configuration

```dart
firebase.https.onRequest(
  name: 'api',
  options: HttpsOptions(
    // 2GB in production, 512MB in development
    memory: Memory.expression(isProduction.thenElse(2048, 512)),
  ),
  (request) async {
    final env = isProduction.value() ? 'production' : 'development';
    return Response.ok('Running in $env mode');
  },
);
```

## Global Options

Use `setGlobalOptions` to set defaults for every function. Per-function options
override these defaults.

```dart
setGlobalOptions(
  const GlobalOptions(
    region: Region(SupportedRegion.europeWest1),
    enforceAppCheck: EnforceAppCheck(true),
  ),
);

firebase.https.onCall(name: 'secureCallable', (request, response) async {
  return CallableResult({'ok': true});
});

firebase.https.onRequest(
  name: 'usEndpoint',
  options: const HttpsOptions(region: Region(SupportedRegion.usCentral1)),
  (request) async => Response.ok('Runs in us-central1'),
);
```

## Firebase Admin SDK

The Functions runtime uses a Firebase Admin SDK app for features such as
callable auth and App Check token verification.

If you do not initialize an Admin SDK app yourself, the runtime creates a
default app with Application Default Credentials and the current Functions
project ID. Application Default Credentials can load a service account JSON file
from the `GOOGLE_APPLICATION_CREDENTIALS` environment variable.

To customize Admin SDK options, initialize the default app before calling
`runFunctions`. The runtime will reuse that app instead of creating another one.

```dart
import 'dart:io';

import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';
import 'package:firebase_functions/firebase_functions.dart';

void main() {
  FirebaseApp.initializeApp(
    options: AppOptions(
      credential: Credential.fromServiceAccount(
        File('path/to/service-account.json'),
      ),
      projectId: 'my-project',
    ),
  );

  runFunctions((firebase) {
    firebase.https.onRequest(
      name: 'hello',
      (request) async => Response.ok('Hello from Dart!'),
    );
  });
}
```

