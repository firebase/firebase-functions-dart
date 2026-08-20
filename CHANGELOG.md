## Unreleased

- Fix `extractAuthToken` dropping custom claims from `AuthData.token` for
  verified (non-emulator) ID tokens; custom claims set via
  `auth.setCustomUserClaims()` are now included alongside the standard claims.
- Fix CORS to match the Node.js SDK: preflights echo
  `Access-Control-Request-Headers` instead of sending `*`, which the Fetch spec
  excludes `Authorization` from, breaking authenticated callables in the
  browser; error responses keep their CORS headers.
- **BREAKING:** `Cors` is now `Option<List<Object>>`, accepting exact origins or
  `CorsPattern` regexes, with `corsAllowAnyOrigin`, `corsAnyOriginWildcard` and
  `corsDisabled` for the `cors: true`/`'*'`/`false` equivalents.
- Support dependencies with native build hooks (e.g. `sqlite3`): projects
  declaring an SDK constraint of `^3.13.0` or later now generate a manifest
  `command` pointing at `dart build cli`'s bundle, and require firebase-tools
  15.28.1 or later to deploy. Projects below that constraint keep building with
  `dart compile exe` as before.

## 0.7.0

- **BREAKING:** Replace custom `HttpsError` implementation with
  `HttpResponseException` from `package:google_cloud_shelf`. Surfacing errors
  in HTTP and callable handlers now uses standard `HttpResponseException`
  constructors (e.g., `HttpResponseException.badRequest(...)`,
  `HttpResponseException.unauthorized(...)`).
- Re-export `HttpResponseException` directly from
  `package:firebase_functions/firebase_functions.dart`.
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
- Added `RunFunctionsOptions` with `poweredByHeader` to override the shelf's default.
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
