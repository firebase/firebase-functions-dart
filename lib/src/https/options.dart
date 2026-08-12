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

import '../common/options.dart';
import 'cors.dart';

/// Options for HTTPS functions (onRequest).
class HttpsOptions extends GlobalOptions {
  const HttpsOptions({
    super.concurrency,
    super.cpu,
    super.enforceAppCheck,
    super.ingressSettings,
    super.invoker,
    super.labels,
    super.minInstances,
    super.maxInstances,
    super.memory,
    super.omit,
    super.preserveExternalChanges,
    super.region,
    super.secrets,
    super.serviceAccount,
    super.timeoutSeconds,
    super.vpcConnector,
    super.vpcConnectorEgressSettings,
    this.cors,
  });

  /// CORS configuration for the function.
  ///
  /// See [Cors] for how the origin list is interpreted. When omitted, no CORS
  /// headers are emitted for `onRequest` functions; callable functions default
  /// to allowing any origin.
  final Cors? cors;
}

/// Options for callable functions (onCall).
class CallableOptions extends HttpsOptions {
  const CallableOptions({
    super.concurrency,
    super.cpu,
    super.enforceAppCheck,
    super.ingressSettings,
    super.invoker,
    super.labels,
    super.minInstances,
    super.maxInstances,
    super.memory,
    super.omit,
    super.preserveExternalChanges,
    super.region,
    super.secrets,
    super.serviceAccount,
    super.timeoutSeconds,
    super.vpcConnector,
    super.vpcConnectorEgressSettings,
    super.cors,
    this.consumeAppCheckToken,
    this.heartBeatIntervalSeconds,
  });

  /// Whether to consume the App Check token.
  final ConsumeAppCheckToken? consumeAppCheckToken;

  /// Heartbeat interval in seconds for streaming responses.
  final HeartBeatIntervalSeconds? heartBeatIntervalSeconds;
}

// Type aliases for HTTPS-specific options

/// The set of origins allowed to make cross-origin requests to a function.
///
/// Each entry is either an exact-match origin [String] or a [CorsPattern]
/// regular expression, mirroring `Array<string | RegExp>` in the Node.js SDK.
///
/// - `Cors(<Object>[])` disables CORS, equivalent to `cors: false`. An empty
///   list also wins over the emulator's `enableCors` debug feature.
/// - `Cors(['*'])` emits a literal `Access-Control-Allow-Origin: *` with no
///   `Vary`, equivalent to `cors: '*'`. See [corsAnyOriginWildcard].
/// - [corsAllowAnyOrigin] reflects the request's `Origin` instead, equivalent
///   to `cors: true`. This is the default for callable functions, and the one
///   to prefer: a reflected origin also works for credentialed requests.
/// - `Cors(['https://example.com'])` — a **single** entry — emits that origin
///   unconditionally and lets the browser reject a mismatch, matching how the
///   Node.js SDK collapses a one-element allow-list.
/// - `Cors(['https://a.com', 'https://b.com'])` reflects the request's origin
///   only when it matches, and omits the header otherwise.
/// - `Cors([CorsPattern(r'^https://.*\.example\.com$')])` matches by regex.
///
/// The value may also come from a parameter or expression, in which case it is
/// resolved once per request. If resolution fails, CORS is disabled for that
/// request and a warning is logged.
typedef Cors = Option<List<Object>>;
typedef ConsumeAppCheckToken = Option<bool>;
typedef HeartBeatIntervalSeconds = Option<int>;
