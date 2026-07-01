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

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart';

import '../common/cloud_event.dart';
import '../firebase.dart';
import 'config_update_data.dart';
import 'options.dart';

/// Remote Config triggers namespace.
///
/// Provides methods to define Remote Config-triggered Cloud Functions.
class RemoteConfigNamespace extends FunctionsNamespace {
  const RemoteConfigNamespace(super.firebase);

  /// Creates a function triggered by Remote Config updates.
  ///
  /// The handler receives a [CloudEvent] containing the [ConfigUpdateData].
  ///
  /// Example:
  /// ```dart
  /// firebase.remoteConfig.onConfigUpdated(
  ///   (event) async {
  ///     final data = event.data;
  ///     print('Config updated: version ${data?.versionNumber}');
  ///     print('Updated by: ${data?.updateUser.email}');
  ///   },
  /// );
  /// ```
  void onConfigUpdated(
    Future<void> Function(CloudEvent<ConfigUpdateData> event) handler, {
    // ignore: experimental_member_use
    @mustBeConst RemoteConfigOptions? options = const RemoteConfigOptions(),
  }) {
    const functionName = 'onConfigUpdated';

    firebase.registerFunction(functionName, (request) async {
      try {
        // Read and parse CloudEvent
        final json = await parseAndValidateCloudEvent(request);

        // Verify it's a Remote Config event
        if (!_isRemoteConfigEvent(json['type'] as String)) {
          return Response(
            400,
            body: 'Invalid event type for Remote Config: ${json['type']}',
          );
        }

        // Parse CloudEvent with ConfigUpdateData
        final event = CloudEvent<ConfigUpdateData>.fromJson(
          json,
          ConfigUpdateData.fromJson,
        );

        // Execute handler
        await handler(event);

        // Return success
        return Response.ok('');
      } on FormatException catch (e) {
        return Response(400, body: 'Invalid CloudEvent: ${e.message}');
      }
    });
  }

  /// Checks if the CloudEvent type is a Remote Config update event.
  bool _isRemoteConfigEvent(String type) =>
      type == 'google.firebase.remoteconfig.remoteConfig.v1.updated';
}
