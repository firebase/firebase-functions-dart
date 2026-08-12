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

import 'package:firebase_functions/firebase_functions.dart';

/// The origin the allow-list examples trust. Change this to wherever you serve
/// `public/index.html` from, then redeploy.
const trustedOrigin = 'http://localhost:8000';

void main() async {
  await runFunctions((firebase) {
    // ---------------------------------------------------------------------
    // Off (the default for onRequest)
    // ---------------------------------------------------------------------

    /// No `cors` option, so no CORS headers. A browser on another origin is
    /// blocked. Under the emulator this one *does* get headers, because the
    /// enableCors debug feature turns CORS on for functions that never
    /// configured it.
    firebase.https.onRequest(
      name: 'corsOff',
      (request) async => Response.ok('corsOff'),
    );

    /// Explicitly disabled. Stays off even under the emulator, which is the
    /// point: local behaviour matches production.
    firebase.https.onRequest(
      name: 'corsOptOut',
      options: const HttpsOptions(cors: corsDisabled),
      (request) async => Response.ok('corsOptOut'),
    );

    // ---------------------------------------------------------------------
    // Any origin, two flavours
    // ---------------------------------------------------------------------

    /// Reflects the request's `Origin`, like `cors: true` in the Node.js SDK.
    /// Prefer this: it also works for credentialed requests.
    firebase.https.onRequest(
      name: 'corsReflectAny',
      options: const HttpsOptions(cors: corsAllowAnyOrigin),
      (request) async => Response.ok('corsReflectAny'),
    );

    /// A literal `Access-Control-Allow-Origin: *`, like `cors: '*'`. No `Vary`,
    /// because the response does not depend on the origin.
    firebase.https.onRequest(
      name: 'corsWildcard',
      options: const HttpsOptions(cors: corsAnyOriginWildcard),
      (request) async => Response.ok('corsWildcard'),
    );

    // ---------------------------------------------------------------------
    // Allow-lists
    // ---------------------------------------------------------------------

    /// A single entry is emitted statically: the header is always this origin,
    /// whoever asks, and the browser rejects a mismatch. Matches how the
    /// Node.js SDK collapses a one-element array.
    firebase.https.onRequest(
      name: 'corsSingleOrigin',
      options: const HttpsOptions(cors: Cors([trustedOrigin])),
      (request) async => Response.ok('corsSingleOrigin'),
    );

    /// Two or more entries match dynamically: the origin is reflected when it
    /// is on the list, and the header is omitted otherwise.
    firebase.https.onRequest(
      name: 'corsAllowList',
      options: const HttpsOptions(
        cors: Cors([trustedOrigin, 'https://example.com']),
      ),
      (request) async => Response.ok('corsAllowList'),
    );

    /// Regex origins. `RegExp` has no const constructor and options must be
    /// const, so the pattern is held as a string and compiled on first use.
    firebase.https.onRequest(
      name: 'corsPattern',
      options: const HttpsOptions(
        cors: Cors([CorsPattern(r'^http://localhost:\d+$')]),
      ),
      (request) async => Response.ok('corsPattern'),
    );

    // ---------------------------------------------------------------------
    // Error paths: headers must survive
    // ---------------------------------------------------------------------

    /// Throws a 401. The CORS headers must still be present, or the browser
    /// reports an opaque CORS failure and hides the real status from you.
    firebase.https.onRequest(
      name: 'corsThrows401',
      options: const HttpsOptions(cors: corsAllowAnyOrigin),
      (request) async => throw HttpResponseException.unauthorized(),
    );

    /// Throws an unhandled error, becoming a 500. Same requirement.
    firebase.https.onRequest(
      name: 'corsThrows500',
      options: const HttpsOptions(cors: corsAllowAnyOrigin),
      (request) async => throw StateError('deliberate failure'),
    );

    // ---------------------------------------------------------------------
    // Callable
    // ---------------------------------------------------------------------

    /// Callables default to reflecting any origin and advertise `POST` only.
    /// Sending an `Authorization` header makes the browser preflight, which is
    /// the case the wildcard `Allow-Headers` used to break.
    firebase.https.onCall(
      name: 'corsCallable',
      (request, response) async => CallableResult({'ok': true}),
    );
  });
}
