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
import 'message.dart';
import 'options.dart';

/// Pub/Sub triggers namespace.
///
/// Provides methods to define Pub/Sub-triggered Cloud Functions.
class PubSubNamespace extends FunctionsNamespace {
  const PubSubNamespace(super.firebase);

  /// Creates a function triggered by Pub/Sub messages.
  ///
  /// The handler receives a [CloudEvent] containing the [PubsubMessage].
  ///
  /// Example:
  /// ```dart
  /// firebase.pubsub.onMessagePublished(
  ///   topic: 'my-topic',
  ///   (event) async {
  ///     final message = event.data;
  ///     print('Received: ${message.textData}');
  ///     print('Attributes: ${message.attributes}');
  ///   },
  /// );
  /// ```
  void onMessagePublished(
    Future<void> Function(CloudEvent<PubsubMessage> event) handler, {
    // ignore: experimental_member_use
    @mustBeConst required String topic,
    // ignore: experimental_member_use
    @mustBeConst PubSubOptions? options = const PubSubOptions(),
  }) {
    // Generate function name from topic
    final functionName = _topicToFunctionName(topic);

    firebase.registerFunction(functionName, (request) async {
      try {
        // Read and parse CloudEvent
        final json = await parseAndValidateCloudEvent(request);

        // Verify it's a Pub/Sub event
        if (!_isPubSubEvent(json['type'] as String)) {
          return Response(
            400,
            body: 'Invalid event type for Pub/Sub: ${json['type']}',
          );
        }

        // Parse CloudEvent with PubsubMessage data
        final event = CloudEvent<PubsubMessage>.fromJson(
          json,
          PubsubMessage.fromJson,
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

  /// Converts a topic name to a function name.
  ///
  /// Examples:
  /// - 'my-topic' -> 'onMessagePublished_mytopic'
  /// - 'projects/my-project/topics/my-topic' -> 'onMessagePublished_mytopic'
  String _topicToFunctionName(String topic) {
    // Extract just the topic name (last segment)
    final segments = topic.split('/');
    final topicName = segments.last;

    // Remove hyphens to match Node.js behavior
    final sanitizedTopic = topicName.replaceAll('-', '');

    return 'onMessagePublished_$sanitizedTopic';
  }

  /// Checks if the CloudEvent type is a Pub/Sub message event.
  bool _isPubSubEvent(String type) =>
      type == 'google.cloud.pubsub.topic.v1.messagePublished';
}
