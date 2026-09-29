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

/// DocumentOptions extend GlobalOptions with provided document and optional database and namespace.
class DocumentOptions extends EventHandlerOptions {
  const DocumentOptions({
    required this.document,
    this.database,
    this.namespace,
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

  /// The document path (e.g., "users/{userId}" or "users/user123").
  /// Supports path patterns with wildcards.
  final String document;

  /// The Firestore database (default: "(default)").
  final String? database;

  /// The Firestore namespace (default: "(default)").
  final String? namespace;
}
