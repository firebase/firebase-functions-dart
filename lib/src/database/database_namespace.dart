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
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart';

import '../common/cloud_event.dart';
import '../firebase.dart';
import 'data_snapshot.dart';
import 'event.dart';
import 'options.dart';

/// CloudEvent type for database value written events.
const writtenEventType = 'google.firebase.database.ref.v1.written';

/// CloudEvent type for database value created events.
const createdEventType = 'google.firebase.database.ref.v1.created';

/// CloudEvent type for database value updated events.
const updatedEventType = 'google.firebase.database.ref.v1.updated';

/// CloudEvent type for database value deleted events.
const deletedEventType = 'google.firebase.database.ref.v1.deleted';

/// Realtime Database triggers namespace.
///
/// Provides methods to define Realtime Database-triggered Cloud Functions.
class DatabaseNamespace extends FunctionsNamespace {
  const DatabaseNamespace(super.firebase);

  /// Event handler that triggers when data is created in Realtime Database.
  ///
  /// The handler receives a [DatabaseEvent] containing a [DataSnapshot].
  ///
  /// Example:
  /// ```dart
  /// firebase.database.onValueCreated(
  ///   ref: 'users/{userId}',
  ///   (event) async {
  ///     // Access data
  ///     final data = event.data?.val();
  ///     print('New data: $data');
  ///
  ///     // Access path parameters
  ///     print('User ID: ${event.params['userId']}');
  ///
  ///     // Access reference metadata
  ///     print('Reference path: ${event.ref}');
  ///   },
  /// );
  /// ```
  void onValueCreated(
    Future<void> Function(DatabaseEvent<DataSnapshot?> event) handler, {

    /// The database reference path to trigger on.
    /// Supports wildcards: '/users/{userId}', '/users/{userId}/posts/{postId}'
    // ignore: experimental_member_use
    @mustBeConst required String ref,

    /// Options that can be set on an individual event-handling function.
    // ignore: experimental_member_use
    @mustBeConst ReferenceOptions? options,
  }) {
    final functionName = _refToFunctionName('onValueCreated', ref);
    final instance = options?.instance ?? '*';

    firebase.registerFunction(functionName, (request) async {
      try {
        final isBinaryMode = request.headers.containsKey('ce-type');

        if (isBinaryMode) {
          final ceType = request.headers['ce-type'];

          if (ceType != null && !_isCreatedEvent(ceType)) {
            return Response(
              400,
              body: 'Invalid event type for Database onValueCreated: $ceType',
            );
          }

          final ceId = request.headers['ce-id'] ?? '';
          final ceSource = request.headers['ce-source'] ?? '';
          final ceTime =
              request.headers['ce-time'] ?? DateTime.now().toIso8601String();
          final ceSubject = request.headers['ce-subject'];
          final refPath = request.headers['ce-ref'] ?? '';
          final instanceName = request.headers['ce-instance'] ?? instance;
          final databaseHost = request.headers['ce-firebasedatabasehost'] ?? '';
          final location = request.headers['ce-location'] ?? 'us-central1';

          final params = _extractParams(ref, refPath);

          // Parse JSON body
          DataSnapshot? snapshot;
          try {
            final bodyString = await request.readAsString();
            if (bodyString.isNotEmpty) {
              final bodyJson = jsonDecode(bodyString) as Map<String, dynamic>;
              // For created events, the new data is in 'delta'
              final deltaData = bodyJson['delta'];
              snapshot = DataSnapshot(
                instance: instanceName,
                ref: refPath,
                data: deltaData,
              );
            }
          } catch (_) {
            // Body parsing failed - snapshot remains null
          }

          final event = DatabaseEvent<DataSnapshot?>(
            data: snapshot,
            id: ceId,
            source: ceSource,
            specversion: '1.0',
            subject: ceSubject,
            time: DateTime.parse(ceTime),
            type: ceType ?? createdEventType,
            firebaseDatabaseHost: databaseHost,
            instance: instanceName,
            ref: refPath,
            location: location,
            params: params,
          );

          await handler(event);

          return Response.ok('');
        } else {
          // Structured content mode: full CloudEvent in JSON body
          final json = await parseAndValidateCloudEvent(request);

          if (!_isCreatedEvent(json['type'] as String)) {
            return Response(
              400,
              body:
                  'Invalid event type for Database onValueCreated: ${json['type']}',
            );
          }

          final eventData = json['data'] as Map<String, dynamic>?;
          final deltaData = eventData?['delta'];

          final refPath = json['ref'] as String? ?? '';
          final instanceName = json['instance'] as String? ?? instance;

          final snapshot = DataSnapshot(
            instance: instanceName,
            ref: refPath,
            data: deltaData,
          );

          final params = _extractParams(ref, refPath);

          final event = DatabaseEvent<DataSnapshot?>(
            data: snapshot,
            id: json['id'] as String,
            source: json['source'] as String,
            specversion: json['specversion'] as String,
            subject: json['subject'] as String?,
            time: DateTime.parse(json['time'] as String),
            type: json['type'] as String,
            firebaseDatabaseHost: json['firebasedatabasehost'] as String? ?? '',
            instance: instanceName,
            ref: refPath,
            location: json['location'] as String? ?? 'us-central1',
            params: params,
          );

          await handler(event);
          return Response.ok('');
        }
      } on FormatException catch (e) {
        return Response(400, body: 'Invalid CloudEvent: ${e.message}');
      }
    }, refPattern: _normalizeRefPattern(ref));
  }

  /// Event handler that triggers when data is updated in Realtime Database.
  ///
  /// The handler receives a [DatabaseEvent] containing a [Change] object
  /// with `before` and `after` snapshots.
  ///
  /// Example:
  /// ```dart
  /// firebase.database.onValueUpdated(
  ///   ref: 'users/{userId}',
  ///   (event) async {
  ///     final before = event.data?.before?.val();
  ///     final after = event.data?.after?.val();
  ///
  ///     print('User ${event.params['userId']} updated');
  ///     print('Old value: $before');
  ///     print('New value: $after');
  ///   },
  /// );
  /// ```
  void onValueUpdated(
    Future<void> Function(DatabaseEvent<Change<DataSnapshot>?> event) handler, {

    /// The database reference path to trigger on.
    /// Supports wildcards: '/users/{userId}', '/users/{userId}/posts/{postId}'
    // ignore: experimental_member_use
    @mustBeConst required String ref,

    /// Options that can be set on an individual event-handling function.
    // ignore: experimental_member_use
    @mustBeConst ReferenceOptions? options,
  }) {
    final functionName = _refToFunctionName('onValueUpdated', ref);
    final instance = options?.instance ?? '*';

    firebase.registerFunction(functionName, (request) async {
      try {
        final isBinaryMode = request.headers.containsKey('ce-type');

        if (isBinaryMode) {
          final ceType = request.headers['ce-type'];

          if (ceType != null && !_isUpdatedEvent(ceType)) {
            return Response(
              400,
              body: 'Invalid event type for Database onValueUpdated: $ceType',
            );
          }

          final ceId = request.headers['ce-id'] ?? '';
          final ceSource = request.headers['ce-source'] ?? '';
          final ceTime =
              request.headers['ce-time'] ?? DateTime.now().toIso8601String();
          final ceSubject = request.headers['ce-subject'];
          final refPath = request.headers['ce-ref'] ?? '';
          final instanceName = request.headers['ce-instance'] ?? instance;
          final databaseHost = request.headers['ce-firebasedatabasehost'] ?? '';
          final location = request.headers['ce-location'] ?? 'us-central1';

          final params = _extractParams(ref, refPath);

          // Parse JSON body
          Change<DataSnapshot>? change;
          try {
            final bodyString = await request.readAsString();
            if (bodyString.isNotEmpty) {
              final bodyJson = jsonDecode(bodyString) as Map<String, dynamic>;
              // For update events: 'data' is before state, 'delta' is the change
              final beforeData = bodyJson['data'];
              final deltaData = bodyJson['delta'];
              // Apply delta to get after state
              final afterData = _applyDelta(beforeData, deltaData);

              final beforeSnapshot = DataSnapshot(
                instance: instanceName,
                ref: refPath,
                data: beforeData,
              );
              final afterSnapshot = DataSnapshot(
                instance: instanceName,
                ref: refPath,
                data: afterData,
              );
              change = Change<DataSnapshot>(
                before: beforeSnapshot,
                after: afterSnapshot,
              );
            }
          } catch (_) {
            // Body parsing failed - change remains null
          }

          final event = DatabaseEvent<Change<DataSnapshot>?>(
            data: change,
            id: ceId,
            source: ceSource,
            specversion: '1.0',
            subject: ceSubject,
            time: DateTime.parse(ceTime),
            type: ceType ?? updatedEventType,
            firebaseDatabaseHost: databaseHost,
            instance: instanceName,
            ref: refPath,
            location: location,
            params: params,
          );

          await handler(event);

          return Response.ok('');
        } else {
          // Structured content mode: full CloudEvent in JSON body
          final json = await parseAndValidateCloudEvent(request);

          if (!_isUpdatedEvent(json['type'] as String)) {
            return Response(
              400,
              body:
                  'Invalid event type for Database onValueUpdated: ${json['type']}',
            );
          }

          final eventData = json['data'] as Map<String, dynamic>?;
          final beforeData = eventData?['data'];
          final deltaData = eventData?['delta'];
          final afterData = _applyDelta(beforeData, deltaData);

          final refPath = json['ref'] as String? ?? '';
          final instanceName = json['instance'] as String? ?? instance;

          final beforeSnapshot = DataSnapshot(
            instance: instanceName,
            ref: refPath,
            data: beforeData,
          );
          final afterSnapshot = DataSnapshot(
            instance: instanceName,
            ref: refPath,
            data: afterData,
          );
          final change = Change<DataSnapshot>(
            before: beforeSnapshot,
            after: afterSnapshot,
          );

          final params = _extractParams(ref, refPath);

          final event = DatabaseEvent<Change<DataSnapshot>?>(
            data: change,
            id: json['id'] as String,
            source: json['source'] as String,
            specversion: json['specversion'] as String,
            subject: json['subject'] as String?,
            time: DateTime.parse(json['time'] as String),
            type: json['type'] as String,
            firebaseDatabaseHost: json['firebasedatabasehost'] as String? ?? '',
            instance: instanceName,
            ref: refPath,
            location: json['location'] as String? ?? 'us-central1',
            params: params,
          );

          await handler(event);
          return Response.ok('');
        }
      } catch (e, stackTrace) {
        return Response(
          500,
          body: 'Error processing Database event: $e\n$stackTrace',
        );
      }
    }, refPattern: _normalizeRefPattern(ref));
  }

  /// Event handler that triggers when data is deleted in Realtime Database.
  ///
  /// The handler receives a [DatabaseEvent] containing a [DataSnapshot]
  /// of the deleted data.
  ///
  /// Example:
  /// ```dart
  /// firebase.database.onValueDeleted(
  ///   ref: 'users/{userId}',
  ///   (event) async {
  ///     final deletedData = event.data?.val();
  ///     print('User ${event.params['userId']} deleted');
  ///     print('Final data: $deletedData');
  ///   },
  /// );
  /// ```
  void onValueDeleted(
    Future<void> Function(DatabaseEvent<DataSnapshot?> event) handler, {

    /// The database reference path to trigger on.
    /// Supports wildcards: '/users/{userId}', '/users/{userId}/posts/{postId}'
    // ignore: experimental_member_use
    @mustBeConst required String ref,

    /// Options that can be set on an individual event-handling function.
    // ignore: experimental_member_use
    @mustBeConst ReferenceOptions? options,
  }) {
    final functionName = _refToFunctionName('onValueDeleted', ref);
    final instance = options?.instance ?? '*';

    firebase.registerFunction(functionName, (request) async {
      try {
        final isBinaryMode = request.headers.containsKey('ce-type');

        if (isBinaryMode) {
          final ceType = request.headers['ce-type'];

          if (ceType != null && !_isDeletedEvent(ceType)) {
            return Response(
              400,
              body: 'Invalid event type for Database onValueDeleted: $ceType',
            );
          }

          final ceId = request.headers['ce-id'] ?? '';
          final ceSource = request.headers['ce-source'] ?? '';
          final ceTime =
              request.headers['ce-time'] ?? DateTime.now().toIso8601String();
          final ceSubject = request.headers['ce-subject'];
          final refPath = request.headers['ce-ref'] ?? '';
          final instanceName = request.headers['ce-instance'] ?? instance;
          final databaseHost = request.headers['ce-firebasedatabasehost'] ?? '';
          final location = request.headers['ce-location'] ?? 'us-central1';

          final params = _extractParams(ref, refPath);

          // Parse JSON body
          DataSnapshot? snapshot;
          try {
            final bodyString = await request.readAsString();
            if (bodyString.isNotEmpty) {
              final bodyJson = jsonDecode(bodyString) as Map<String, dynamic>;
              // For delete events, the deleted data is in 'data'
              final deletedData = bodyJson['data'];
              snapshot = DataSnapshot(
                instance: instanceName,
                ref: refPath,
                data: deletedData,
              );
            }
          } catch (_) {
            // Body parsing failed - snapshot remains null
          }

          final event = DatabaseEvent<DataSnapshot?>(
            data: snapshot,
            id: ceId,
            source: ceSource,
            specversion: '1.0',
            subject: ceSubject,
            time: DateTime.parse(ceTime),
            type: ceType ?? deletedEventType,
            firebaseDatabaseHost: databaseHost,
            instance: instanceName,
            ref: refPath,
            location: location,
            params: params,
          );

          await handler(event);

          return Response.ok('');
        } else {
          // Structured content mode: full CloudEvent in JSON body
          final json = await parseAndValidateCloudEvent(request);

          if (!_isDeletedEvent(json['type'] as String)) {
            return Response(
              400,
              body:
                  'Invalid event type for Database onValueDeleted: ${json['type']}',
            );
          }

          final eventData = json['data'] as Map<String, dynamic>?;
          final deletedData = eventData?['data'];

          final refPath = json['ref'] as String? ?? '';
          final instanceName = json['instance'] as String? ?? instance;

          final snapshot = DataSnapshot(
            instance: instanceName,
            ref: refPath,
            data: deletedData,
          );

          final params = _extractParams(ref, refPath);

          final event = DatabaseEvent<DataSnapshot?>(
            data: snapshot,
            id: json['id'] as String,
            source: json['source'] as String,
            specversion: json['specversion'] as String,
            subject: json['subject'] as String?,
            time: DateTime.parse(json['time'] as String),
            type: json['type'] as String,
            firebaseDatabaseHost: json['firebasedatabasehost'] as String? ?? '',
            instance: instanceName,
            ref: refPath,
            location: json['location'] as String? ?? 'us-central1',
            params: params,
          );

          await handler(event);
          return Response.ok('');
        }
      } catch (e, stackTrace) {
        return Response(
          500,
          body: 'Error processing Database event: $e\n$stackTrace',
        );
      }
    }, refPattern: _normalizeRefPattern(ref));
  }

  /// Event handler that triggers on any write to a database reference
  /// (create, update, or delete).
  ///
  /// The handler receives a [DatabaseEvent] containing a [Change] object.
  /// Use `before` and `after` to determine the operation type:
  /// - Create: before is null/empty, after has data
  /// - Update: both before and after have data
  /// - Delete: before has data, after is null/empty
  ///
  /// Example:
  /// ```dart
  /// firebase.database.onValueWritten(
  ///   ref: 'users/{userId}',
  ///   (event) async {
  ///     final before = event.data?.before;
  ///     final after = event.data?.after;
  ///
  ///     if (before == null || !before.exists()) {
  ///       print('Data created');
  ///     } else if (after == null || !after.exists()) {
  ///       print('Data deleted');
  ///     } else {
  ///       print('Data updated');
  ///     }
  ///   },
  /// );
  /// ```
  void onValueWritten(
    Future<void> Function(DatabaseEvent<Change<DataSnapshot>?> event) handler, {

    /// The database reference path to trigger on.
    /// Supports wildcards: '/users/{userId}', '/users/{userId}/posts/{postId}'
    // ignore: experimental_member_use
    @mustBeConst required String ref,

    /// Options that can be set on an individual event-handling function.
    // ignore: experimental_member_use
    @mustBeConst ReferenceOptions? options,
  }) {
    final functionName = _refToFunctionName('onValueWritten', ref);
    final instance = options?.instance ?? '*';

    firebase.registerFunction(functionName, (request) async {
      try {
        final isBinaryMode = request.headers.containsKey('ce-type');

        if (isBinaryMode) {
          final ceType = request.headers['ce-type'];

          if (ceType != null && !_isWrittenEvent(ceType)) {
            return Response(
              400,
              body: 'Invalid event type for Database onValueWritten: $ceType',
            );
          }

          final ceId = request.headers['ce-id'] ?? '';
          final ceSource = request.headers['ce-source'] ?? '';
          final ceTime =
              request.headers['ce-time'] ?? DateTime.now().toIso8601String();
          final ceSubject = request.headers['ce-subject'];
          final refPath = request.headers['ce-ref'] ?? '';
          final instanceName = request.headers['ce-instance'] ?? instance;
          final databaseHost = request.headers['ce-firebasedatabasehost'] ?? '';
          final location = request.headers['ce-location'] ?? 'us-central1';

          final params = _extractParams(ref, refPath);

          // Parse JSON body
          Change<DataSnapshot>? change;
          try {
            final bodyString = await request.readAsString();
            if (bodyString.isNotEmpty) {
              final bodyJson = jsonDecode(bodyString) as Map<String, dynamic>;
              // 'data' is before state, 'delta' is the change
              final beforeData = bodyJson['data'];
              final deltaData = bodyJson['delta'];
              // Apply delta to get after state
              final afterData = _applyDelta(beforeData, deltaData);

              final beforeSnapshot = DataSnapshot(
                instance: instanceName,
                ref: refPath,
                data: beforeData,
              );
              final afterSnapshot = DataSnapshot(
                instance: instanceName,
                ref: refPath,
                data: afterData,
              );

              change = Change<DataSnapshot>(
                before: beforeSnapshot,
                after: afterSnapshot,
              );
            }
          } catch (_) {
            // Body parsing failed - change remains null
          }

          final event = DatabaseEvent<Change<DataSnapshot>?>(
            data: change,
            id: ceId,
            source: ceSource,
            specversion: '1.0',
            subject: ceSubject,
            time: DateTime.parse(ceTime),
            type: ceType ?? writtenEventType,
            firebaseDatabaseHost: databaseHost,
            instance: instanceName,
            ref: refPath,
            location: location,
            params: params,
          );

          await handler(event);

          return Response.ok('');
        } else {
          // Structured content mode: full CloudEvent in JSON body
          final json = await parseAndValidateCloudEvent(request);

          if (!_isWrittenEvent(json['type'] as String)) {
            return Response(
              400,
              body:
                  'Invalid event type for Database onValueWritten: ${json['type']}',
            );
          }

          final eventData = json['data'] as Map<String, dynamic>?;
          final beforeData = eventData?['data'];
          final deltaData = eventData?['delta'];
          final afterData = _applyDelta(beforeData, deltaData);

          final refPath = json['ref'] as String? ?? '';
          final instanceName = json['instance'] as String? ?? instance;

          final beforeSnapshot = DataSnapshot(
            instance: instanceName,
            ref: refPath,
            data: beforeData,
          );
          final afterSnapshot = DataSnapshot(
            instance: instanceName,
            ref: refPath,
            data: afterData,
          );
          final change = Change<DataSnapshot>(
            before: beforeSnapshot,
            after: afterSnapshot,
          );

          final params = _extractParams(ref, refPath);

          final event = DatabaseEvent<Change<DataSnapshot>?>(
            data: change,
            id: json['id'] as String,
            source: json['source'] as String,
            specversion: json['specversion'] as String,
            subject: json['subject'] as String?,
            time: DateTime.parse(json['time'] as String),
            type: json['type'] as String,
            firebaseDatabaseHost: json['firebasedatabasehost'] as String? ?? '',
            instance: instanceName,
            ref: refPath,
            location: json['location'] as String? ?? 'us-central1',
            params: params,
          );

          await handler(event);
          return Response.ok('');
        }
      } catch (e, stackTrace) {
        return Response(
          500,
          body: 'Error processing Database event: $e\n$stackTrace',
        );
      }
    }, refPattern: _normalizeRefPattern(ref));
  }

  /// Normalizes a ref pattern by removing leading/trailing slashes.
  ///
  /// Examples:
  /// - '/messages/{messageId}' -> 'messages/{messageId}'
  /// - 'users/{userId}/' -> 'users/{userId}'
  String _normalizeRefPattern(String ref) {
    return ref.replaceAll(RegExp(r'^/+|/+$'), '');
  }

  /// Converts a reference path to a function name.
  ///
  /// Examples:
  /// - '/users/{userId}' -> 'onValueCreated_users_userId'
  /// - '/messages/-Nabc123' -> 'onValueCreated_messages_Nabc123'
  String _refToFunctionName(String eventType, String refPath) {
    // Remove leading/trailing slashes
    final cleaned = refPath.replaceAll(RegExp(r'^/+|/+$'), '');

    // Replace path separators and wildcards with underscores
    final sanitized = cleaned
        .replaceAll('/', '_')
        .replaceAll('{', '')
        .replaceAll('}', '')
        .replaceAll('-', '');

    return '${eventType}_$sanitized';
  }

  /// Checks if the CloudEvent type is a database value created event.
  bool _isCreatedEvent(String type) => type == createdEventType;

  /// Checks if the CloudEvent type is a database value updated event.
  bool _isUpdatedEvent(String type) => type == updatedEventType;

  /// Checks if the CloudEvent type is a database value deleted event.
  bool _isDeletedEvent(String type) => type == deletedEventType;

  /// Checks if the CloudEvent type is a database value written event.
  bool _isWrittenEvent(String type) => type == writtenEventType;

  /// Extracts path parameters from a reference path by matching against a pattern.
  ///
  /// Example:
  /// - pattern: '/users/{userId}'
  /// - refPath: '/users/abc123'
  /// - returns: {'userId': 'abc123'}
  Map<String, String> _extractParams(String pattern, String refPath) {
    final params = <String, String>{};

    // Normalize paths
    final cleanPattern = pattern.replaceAll(RegExp(r'^/+|/+$'), '');
    final cleanRef = refPath.replaceAll(RegExp(r'^/+|/+$'), '');

    final patternParts = cleanPattern.split('/');
    final refParts = cleanRef.split('/');

    if (patternParts.length != refParts.length) {
      return params;
    }

    for (var i = 0; i < patternParts.length; i++) {
      final patternPart = patternParts[i];
      final refPart = refParts[i];

      // Extract parameter name from wildcards like {userId}
      if (patternPart.startsWith('{') && patternPart.endsWith('}')) {
        final paramName = patternPart.substring(1, patternPart.length - 1);
        params[paramName] = refPart;
      }
    }

    return params;
  }

  /// Applies a delta to a data object to produce the new state.
  ///
  /// This follows the Firebase Realtime Database delta format:
  /// - If delta is null, the result is null (deletion)
  /// - If data is null, the result is delta (creation)
  /// - Otherwise, merge delta into data recursively
  dynamic _applyDelta(dynamic data, dynamic delta) {
    if (delta == null) return null;
    if (data == null) return delta;

    if (data is! Map || delta is! Map) {
      return delta;
    }

    final result = Map<String, dynamic>.from(data);

    for (final entry in delta.entries) {
      final key = entry.key.toString();
      final value = entry.value;

      if (value == null) {
        result.remove(key);
      } else if (result[key] is Map && value is Map) {
        result[key] = _applyDelta(result[key], value);
      } else {
        result[key] = value;
      }
    }

    return result;
  }
}
