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
/// - `Cors(['*'])` allows any origin. The request's `Origin` header is
///   reflected back in `Access-Control-Allow-Origin` rather than a literal
///   `*`, matching `cors: true` in the Node.js SDK.
/// - `Cors(['https://example.com'])` allows only the listed origins, compared
///   as exact, case-sensitive strings.
/// - `Cors(<String>[])` disables CORS entirely, equivalent to `cors: false`.
///   An empty list also wins over the emulator's `enableCors` debug feature.
///
/// The value may also come from a parameter or expression, in which case it is
/// resolved once per request. If resolution fails, CORS is disabled for that
/// request and a warning is logged.
///
/// See [corsAllowAnyOrigin] and [corsDisabled] for the two constant shorthands.
typedef Cors = Option<List<String>>;
typedef ConsumeAppCheckToken = Option<bool>;
typedef HeartBeatIntervalSeconds = Option<int>;
