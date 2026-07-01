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
import 'options.dart';
import 'storage_event.dart';
import 'storage_object_data.dart';

/// Cloud Storage triggers namespace.
///
/// Provides methods to define Cloud Storage-triggered Cloud Functions.
class StorageNamespace extends FunctionsNamespace {
  const StorageNamespace(super.firebase);

  /// Creates a function triggered when an object is archived in Cloud Storage.
  ///
  /// The handler receives a [StorageEvent] containing the [StorageObjectData].
  ///
  /// Example:
  /// ```dart
  /// firebase.storage.onObjectArchived(
  ///   bucket: 'my-bucket',
  ///   (event) async {
  ///     print('Object archived: ${event.data?.name}');
  ///   },
  /// );
  /// ```
  void onObjectArchived(
    Future<void> Function(StorageEvent event) handler, {
    // ignore: experimental_member_use
    @mustBeConst required String bucket,
    // ignore: experimental_member_use
    @mustBeConst StorageOptions? options = const StorageOptions(),
  }) {
    _createHandler('onObjectArchived', _eventTypeArchived, bucket, handler);
  }

  /// Creates a function triggered when an object is finalized (created or
  /// overwritten) in Cloud Storage.
  ///
  /// The handler receives a [StorageEvent] containing the [StorageObjectData].
  ///
  /// Example:
  /// ```dart
  /// firebase.storage.onObjectFinalized(
  ///   bucket: 'my-bucket',
  ///   (event) async {
  ///     print('Object finalized: ${event.data?.name}');
  ///     print('Content type: ${event.data?.contentType}');
  ///   },
  /// );
  /// ```
  void onObjectFinalized(
    Future<void> Function(StorageEvent event) handler, {
    // ignore: experimental_member_use
    @mustBeConst required String bucket,
    // ignore: experimental_member_use
    @mustBeConst StorageOptions? options = const StorageOptions(),
  }) {
    _createHandler('onObjectFinalized', _eventTypeFinalized, bucket, handler);
  }

  /// Creates a function triggered when an object is deleted in Cloud Storage.
  ///
  /// The handler receives a [StorageEvent] containing the [StorageObjectData].
  ///
  /// Example:
  /// ```dart
  /// firebase.storage.onObjectDeleted(
  ///   bucket: 'my-bucket',
  ///   (event) async {
  ///     print('Object deleted: ${event.data?.name}');
  ///   },
  /// );
  /// ```
  void onObjectDeleted(
    Future<void> Function(StorageEvent event) handler, {
    // ignore: experimental_member_use
    @mustBeConst required String bucket,
    // ignore: experimental_member_use
    @mustBeConst StorageOptions? options = const StorageOptions(),
  }) {
    _createHandler('onObjectDeleted', _eventTypeDeleted, bucket, handler);
  }

  /// Creates a function triggered when an object's metadata is updated
  /// in Cloud Storage.
  ///
  /// The handler receives a [StorageEvent] containing the [StorageObjectData].
  ///
  /// Example:
  /// ```dart
  /// firebase.storage.onObjectMetadataUpdated(
  ///   bucket: 'my-bucket',
  ///   (event) async {
  ///     print('Metadata updated: ${event.data?.name}');
  ///   },
  /// );
  /// ```
  void onObjectMetadataUpdated(
    Future<void> Function(StorageEvent event) handler, {
    // ignore: experimental_member_use
    @mustBeConst required String bucket,
    // ignore: experimental_member_use
    @mustBeConst StorageOptions? options = const StorageOptions(),
  }) {
    _createHandler(
      'onObjectMetadataUpdated',
      _eventTypeMetadataUpdated,
      bucket,
      handler,
    );
  }

  /// Shared handler creation logic for all storage trigger methods.
  void _createHandler(
    String methodName,
    String expectedEventType,
    String bucket,
    Future<void> Function(StorageEvent event) handler,
  ) {
    final functionName = _bucketToFunctionName(methodName, bucket);

    firebase.registerFunction(functionName, (request) async {
      try {
        // Read and parse CloudEvent
        final json = await parseAndValidateCloudEvent(request);

        // Verify it's the expected Storage event type
        final eventType = json['type'] as String;
        if (!_isStorageEvent(eventType)) {
          return Response(
            400,
            body: 'Invalid event type for Storage: $eventType',
          );
        }

        // Parse CloudEvent with StorageObjectData
        final event = StorageEvent.fromJson(json);

        // Execute handler
        await handler(event);

        // Return success
        return Response.ok('');
      } on FormatException catch (e) {
        return Response(400, body: 'Invalid CloudEvent: ${e.message}');
      }
    });
  }

  /// Converts a bucket name to a function name.
  ///
  /// Examples:
  /// - ('onObjectFinalized', 'my-bucket') -> 'onObjectFinalized_mybucket'
  String _bucketToFunctionName(String methodName, String bucket) {
    final sanitizedBucket = bucket.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
    return '${methodName}_$sanitizedBucket';
  }

  /// Checks if the CloudEvent type is a Storage event.
  bool _isStorageEvent(String type) =>
      type.startsWith('google.cloud.storage.object.v1.');

  static const _eventTypeArchived = 'google.cloud.storage.object.v1.archived';
  static const _eventTypeFinalized = 'google.cloud.storage.object.v1.finalized';
  static const _eventTypeDeleted = 'google.cloud.storage.object.v1.deleted';
  static const _eventTypeMetadataUpdated =
      'google.cloud.storage.object.v1.metadataUpdated';
}
