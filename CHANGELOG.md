## 0.7.0-wip

- **BREAKING:** Replace custom `HttpsError` implementation with `HttpResponseException`
  from `package:google_cloud_shelf`. Surfacing errors in HTTP and callable handlers
  now uses standard `HttpResponseException` constructors (e.g., `HttpResponseException.badRequest(...)`, `HttpResponseException.unauthorized(...)`).
- Re-export `HttpResponseException` directly from `package:firebase_functions/firebase_functions.dart`.
- **BREAKING:** Remove the `logger` field from `logger.dart` and made its
  method functions.

  You can fix this with:

  ```diff
  -  import '../logger/logger.dart';
  +  import '../../logger.dart' as logger;
  ```

- **BREAKING:** Remove the `logger` exports from
  `package:firebase_functions/firebase_functions.dart`.

  You can fix this by explicitly importanting the logging library:

  ```dart
  import '../../logger.dart' as logger;
  ```

- Fix secret name resolution in `defineSecret`: the secret name is now taken
  from the argument passed to `defineSecret` rather than the Dart variable name.
- Fix manifest generation for function options declared with named factories,
  including `Memory.fromInt` in `CallableOptions`.
- Fix manifest discovery for functions registered with cascade syntax (e.g.
  `firebase.https..onCall(...)..onCall(...)`), which were previously omitted
  from `functions.yaml`.
- Emit a build warning when no functions are discovered instead of silently
  writing an endpoint-less `functions.yaml`.
- Fix normalize function names by lowercasing only, not camelCase-to-kebab
- Document and test `ServiceAccount('service-account@')` project-relative
  shorthand parity with the Node.js SDK.

## 0.6.0

- Add `runFunctions` as the primary API.
- Deprecate `fireUp` in favor of `runFunctions`.
- Split `README.md` into multiple pages:
  - `docs/config.md`
  - `docs/triggers.md`
  - `test/README.md`

## 0.5.2

- Add a comment to the generated manifest (`functions.yaml`) to indicate that
  it is managed by this package.
- Add "Learn more" and "Usage" sections to README.md.

## 0.5.1

- Update constraint: `meta: ^1.17.0`
- Remove the use of footnotes in README.md, since they are not supported by
  `package:markdown`.
- Add a landing page for the package examples.

## 0.5.0

- Initial release.
