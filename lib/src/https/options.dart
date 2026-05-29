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

typedef Cors = Option<List<String>>;
typedef ConsumeAppCheckToken = Option<bool>;
typedef HeartBeatIntervalSeconds = Option<int>;
