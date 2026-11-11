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

/// ReferenceOptions extend GlobalOptions with provided ref and optional instance.
///
/// Used to configure Realtime Database event triggers.
class ReferenceOptions extends EventHandlerOptions {
  const ReferenceOptions({
    this.instance,
    super.concurrency,
    super.cpu,
    super.ingressSettings,
    super.invoker,
    super.labels,
    super.minInstances,
    super.maxInstances,
    super.memory,
    super.omit,
    super.preserveExternalChanges,
    super.region,
    super.retry,
    super.secrets,
    super.serviceAccount,
    super.timeoutSeconds,
    super.vpcConnector,
    super.vpcConnectorEgressSettings,
  });

  /// Specify the handler to trigger on a database instance(s).
  ///
  /// If present, this value can either be a single instance or a pattern.
  /// Examples: 'my-instance-1', 'my-instance-*'
  ///
  /// Note: The capture syntax cannot be used for 'instance'.
  /// If not specified, defaults to '*' (all instances).
  final String? instance;
}
