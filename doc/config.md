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

## Function Service Account

Use the `serviceAccount` option to choose which service account a function runs
as. This matches the Firebase Functions Node.js SDK format: pass either the full
service account email or the project-relative shorthand ending in `@`.

```dart
firebase.https.onRequest(
  name: 'hello',
  options: const HttpsOptions(
    // Expands during deployment to:
    // my-account@<project-id>.iam.gserviceaccount.com
    serviceAccount: ServiceAccount('my-account@'),
  ),
  (request) async => Response.ok('Hello from Dart!'),
);
```

You can also provide the full email when the service account is not
project-relative:

```dart
firebase.https.onRequest(
  name: 'helloWithFullServiceAccount',
  options: const HttpsOptions(
    serviceAccount: ServiceAccount(
      'my-account@my-project.iam.gserviceaccount.com',
    ),
  ),
  (request) async => Response.ok('Hello from Dart!'),
);
```

Do not strip the trailing `@` from the shorthand form. `my-account@` is the
cross-SDK shorthand; `my-account` is not equivalent.

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


## Native Dependencies (Build Hooks)

Some packages ship a [build hook](https://dart.dev/interop/c-interop) that
compiles a native library at build time — `sqlite3` is a common example. These
packages cannot be built with `dart compile exe`, which is what deploying a
Dart functions project normally uses:

```
'dart compile' does not support build hooks, use 'dart build' instead.
Packages with build hooks: sqlite3.
```

This applies even when the package is only a transitive dependency, and even
when your own code never imports it.

To deploy such a project, raise the SDK constraint in your functions
`pubspec.yaml` to `^3.13.0` or later:

```yaml
environment:
  sdk: ^3.13.0
```

The Firebase CLI then builds with `dart build cli`, which runs build hooks
while cross-compiling for Cloud Run. Dart 3.13 is required because that is the
release where `dart build cli` gained the `--target-os` and `--target-arch`
flags.

Projects that declare a lower constraint keep building with `dart compile exe`
exactly as before, so this is opt-in — you only need Dart 3.13 if you actually
depend on a package with a build hook. The decision is made from the constraint
your project declares, not from the Dart SDK installed on the machine running
the deploy, so a project builds the same way everywhere.

See [example/sqlite3](https://github.com/firebase/firebase-functions-dart/tree/main/example/sqlite3)
for a working project.
