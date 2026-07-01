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
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart';

import '../common/cloud_event.dart';
import '../firebase.dart';
import 'document_snapshot.dart';
import 'event.dart';
import 'options.dart';
import 'protobuf_parser.dart';

/// Parsed CloudEvent headers from a binary-mode Firestore request.
class _FirestoreHeaders {
  _FirestoreHeaders({
    required this.id,
    required this.source,
    required this.time,
    required this.type,
    required this.documentPath,
    required this.database,
    required this.namespace,
    this.subject,
    this.authType,
    this.authId,
  });

  final String id;
  final String source;
  final String time;
  final String type;
  final String documentPath;
  final String database;
  final String namespace;
  final String? subject;
  final String? authType;
  final String? authId;
}

/// Firestore triggers namespace.
///
/// Provides methods to define Firestore-triggered Cloud Functions.
class FirestoreNamespace extends FunctionsNamespace {
  const FirestoreNamespace(super.firebase);

  /// Event handler that triggers when a document is created in Firestore.
  ///
  /// The handler receives a [FirestoreEvent] containing an [EmulatorDocumentSnapshot].
  ///
  /// Example:
  /// ```dart
  /// firebase.firestore.onDocumentCreated(
  ///   document: 'users/{userId}',
  ///   (event) async {
  ///     // Access document data (similar to Node.js)
  ///     final data = event.data?.data();
  ///     print('User data: $data');
  ///     print('User name: ${data?['name']}');
  ///
  ///     // Access path parameters
  ///     print('User ID: ${event.params['userId']}');
  ///
  ///     // Access document metadata
  ///     print('Document path: ${event.document}');
  ///     print('Document ID: ${event.data?.id}');
  ///   },
  /// );
  /// ```
  void onDocumentCreated(
    Future<void> Function(FirestoreEvent<EmulatorDocumentSnapshot?> event)
    handler, {

    /// The Firestore document path to trigger on.
    /// Supports wildcards: 'users/{userId}', 'users/{userId}/posts/{postId}'
    // ignore: experimental_member_use
    @mustBeConst required String document,

    /// Options that can be set on an individual event-handling function.
    // ignore: experimental_member_use
    @mustBeConst DocumentOptions? options,
  }) {
    _registerDocumentHandler(
      methodName: 'onDocumentCreated',
      document: document,
      validateEventType: _isFirestoreCreatedEvent,
      withAuthContext: false,
      handler: handler,
    );
  }

  /// Event handler that triggers when a document is updated in Firestore.
  ///
  /// The handler receives a [FirestoreEvent] containing a [Change] object
  /// with `before` and `after` snapshots.
  ///
  /// Example:
  /// ```dart
  /// firebase.firestore.onDocumentUpdated(
  ///   document: 'users/{userId}',
  ///   (event) async {
  ///     final before = event.data?.before.data();
  ///     final after = event.data?.after.data();
  ///
  ///     print('User ${event.params['userId']} updated');
  ///     print('Old name: ${before?['name']}');
  ///     print('New name: ${after?['name']}');
  ///   },
  /// );
  /// ```
  void onDocumentUpdated(
    Future<void> Function(
      FirestoreEvent<Change<EmulatorDocumentSnapshot>?> event,
    )
    handler, {

    /// The Firestore document path to trigger on.
    /// Supports wildcards: 'users/{userId}', 'users/{userId}/posts/{postId}'
    // ignore: experimental_member_use
    @mustBeConst required String document,

    /// Options that can be set on an individual event-handling function.
    // ignore: experimental_member_use
    @mustBeConst DocumentOptions? options,
  }) {
    _registerChangeHandler(
      methodName: 'onDocumentUpdated',
      document: document,
      validateEventType: _isFirestoreUpdatedEvent,
      withAuthContext: false,
      handler: handler,
    );
  }

  /// Event handler that triggers when a document is deleted in Firestore.
  ///
  /// The handler receives a [FirestoreEvent] containing the deleted document snapshot.
  ///
  /// Example:
  /// ```dart
  /// firebase.firestore.onDocumentDeleted(
  ///   document: 'users/{userId}',
  ///   (event) async {
  ///     final deletedData = event.data?.data();
  ///     print('User ${event.params['userId']} deleted');
  ///     print('Final data: $deletedData');
  ///   },
  /// );
  /// ```
  void onDocumentDeleted(
    Future<void> Function(FirestoreEvent<EmulatorDocumentSnapshot?> event)
    handler, {

    /// The Firestore document path to trigger on.
    /// Supports wildcards: 'users/{userId}', 'users/{userId}/posts/{postId}'
    // ignore: experimental_member_use
    @mustBeConst required String document,

    /// Options that can be set on an individual event-handling function.
    // ignore: experimental_member_use
    @mustBeConst DocumentOptions? options,
  }) {
    _registerDocumentHandler(
      methodName: 'onDocumentDeleted',
      document: document,
      validateEventType: _isFirestoreDeletedEvent,
      withAuthContext: false,
      handler: handler,
    );
  }

  /// Event handler that triggers on any write to a document (create, update, or delete).
  ///
  /// The handler receives a [FirestoreEvent] containing a [Change] object.
  /// Use `before.exists` and `after.exists` to determine the operation type.
  ///
  /// Example:
  /// ```dart
  /// firebase.firestore.onDocumentWritten(
  ///   document: 'users/{userId}',
  ///   (event) async {
  ///     final before = event.data?.before;
  ///     final after = event.data?.after;
  ///
  ///     if (before == null || !before.exists) {
  ///       print('Document created');
  ///     } else if (after == null || !after.exists) {
  ///       print('Document deleted');
  ///     } else {
  ///       print('Document updated');
  ///     }
  ///   },
  /// );
  /// ```
  void onDocumentWritten(
    Future<void> Function(
      FirestoreEvent<Change<EmulatorDocumentSnapshot>?> event,
    )
    handler, {

    /// The Firestore document path to trigger on.
    /// Supports wildcards: 'users/{userId}', 'users/{userId}/posts/{postId}'
    // ignore: experimental_member_use
    @mustBeConst required String document,

    /// Options that can be set on an individual event-handling function.
    // ignore: experimental_member_use
    @mustBeConst DocumentOptions? options,
  }) {
    _registerChangeHandler(
      methodName: 'onDocumentWritten',
      document: document,
      validateEventType: _isFirestoreWrittenEvent,
      withAuthContext: false,
      handler: handler,
    );
  }

  /// Event handler that triggers when a document is created in Firestore,
  /// with authentication context.
  ///
  /// Similar to [onDocumentCreated], but the handler receives a
  /// [FirestoreAuthEvent] that includes [AuthType] and an optional auth ID
  /// identifying the principal that triggered the write.
  ///
  /// Example:
  /// ```dart
  /// firebase.firestore.onDocumentCreatedWithAuthContext(
  ///   document: 'users/{userId}',
  ///   (event) async {
  ///     print('Auth type: ${event.authType}');
  ///     print('Auth ID: ${event.authId}');
  ///     final data = event.data?.data();
  ///     print('Document created: ${event.document}');
  ///   },
  /// );
  /// ```
  void onDocumentCreatedWithAuthContext(
    Future<void> Function(FirestoreAuthEvent<EmulatorDocumentSnapshot?> event)
    handler, {
    // ignore: experimental_member_use
    @mustBeConst required String document,
    // ignore: experimental_member_use
    @mustBeConst DocumentOptions? options,
  }) {
    _registerDocumentHandler(
      methodName: 'onDocumentCreatedWithAuthContext',
      document: document,
      validateEventType: _isFirestoreCreatedEvent,
      withAuthContext: true,
      handler: handler,
    );
  }

  /// Event handler that triggers when a document is updated in Firestore,
  /// with authentication context.
  ///
  /// Similar to [onDocumentUpdated], but the handler receives a
  /// [FirestoreAuthEvent] that includes [AuthType] and an optional auth ID.
  ///
  /// Example:
  /// ```dart
  /// firebase.firestore.onDocumentUpdatedWithAuthContext(
  ///   document: 'users/{userId}',
  ///   (event) async {
  ///     print('Auth type: ${event.authType}');
  ///     final before = event.data?.before.data();
  ///     final after = event.data?.after.data();
  ///   },
  /// );
  /// ```
  void onDocumentUpdatedWithAuthContext(
    Future<void> Function(
      FirestoreAuthEvent<Change<EmulatorDocumentSnapshot>?> event,
    )
    handler, {
    // ignore: experimental_member_use
    @mustBeConst required String document,
    // ignore: experimental_member_use
    @mustBeConst DocumentOptions? options,
  }) {
    _registerChangeHandler(
      methodName: 'onDocumentUpdatedWithAuthContext',
      document: document,
      validateEventType: _isFirestoreUpdatedEvent,
      withAuthContext: true,
      handler: handler,
    );
  }

  /// Event handler that triggers when a document is deleted in Firestore,
  /// with authentication context.
  ///
  /// Similar to [onDocumentDeleted], but the handler receives a
  /// [FirestoreAuthEvent] that includes [AuthType] and an optional auth ID.
  ///
  /// Example:
  /// ```dart
  /// firebase.firestore.onDocumentDeletedWithAuthContext(
  ///   document: 'users/{userId}',
  ///   (event) async {
  ///     print('Auth type: ${event.authType}');
  ///     print('Deleted by: ${event.authId}');
  ///   },
  /// );
  /// ```
  void onDocumentDeletedWithAuthContext(
    Future<void> Function(FirestoreAuthEvent<EmulatorDocumentSnapshot?> event)
    handler, {
    // ignore: experimental_member_use
    @mustBeConst required String document,
    // ignore: experimental_member_use
    @mustBeConst DocumentOptions? options,
  }) {
    _registerDocumentHandler(
      methodName: 'onDocumentDeletedWithAuthContext',
      document: document,
      validateEventType: _isFirestoreDeletedEvent,
      withAuthContext: true,
      handler: handler,
    );
  }

  /// Event handler that triggers on any write to a document (create, update,
  /// or delete), with authentication context.
  ///
  /// Similar to [onDocumentWritten], but the handler receives a
  /// [FirestoreAuthEvent] that includes [AuthType] and an optional auth ID.
  ///
  /// Example:
  /// ```dart
  /// firebase.firestore.onDocumentWrittenWithAuthContext(
  ///   document: 'users/{userId}',
  ///   (event) async {
  ///     print('Auth type: ${event.authType}');
  ///     print('Auth ID: ${event.authId}');
  ///     final before = event.data?.before;
  ///     final after = event.data?.after;
  ///   },
  /// );
  /// ```
  void onDocumentWrittenWithAuthContext(
    Future<void> Function(
      FirestoreAuthEvent<Change<EmulatorDocumentSnapshot>?> event,
    )
    handler, {
    // ignore: experimental_member_use
    @mustBeConst required String document,
    // ignore: experimental_member_use
    @mustBeConst DocumentOptions? options,
  }) {
    _registerChangeHandler(
      methodName: 'onDocumentWrittenWithAuthContext',
      document: document,
      validateEventType: _isFirestoreWrittenEvent,
      withAuthContext: true,
      handler: handler,
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Extracts and validates all `ce-*` headers from a binary-mode request.
  ///
  /// Returns `null` if required headers (`ce-id`, `ce-source`, `ce-time`,
  /// `ce-document`) are missing.
  _FirestoreHeaders? _extractHeaders(Request request) {
    final ceId = request.headers['ce-id'];
    final ceSource = request.headers['ce-source'];
    final ceTime = request.headers['ce-time'];
    final documentPath = request.headers['ce-document'];

    if (ceId == null ||
        ceSource == null ||
        ceTime == null ||
        documentPath == null) {
      return null;
    }

    return _FirestoreHeaders(
      id: ceId,
      source: ceSource,
      time: ceTime,
      type: request.headers['ce-type']!,
      documentPath: documentPath,
      database: request.headers['ce-database'] ?? '(default)',
      namespace: request.headers['ce-namespace'] ?? '(default)',
      subject: request.headers['ce-subject'],
      authType: request.headers['ce-authtype'],
      authId: request.headers['ce-authid'],
    );
  }

  /// Reads and parses the protobuf body from a request.
  ///
  /// Returns the parsed map with `'value'` and/or `'old_value'` keys,
  /// or `null` if the body is empty or parsing fails.
  Future<Map<String, EmulatorDocumentSnapshot?>?> _parseBody(
    Request request,
  ) async {
    try {
      final bodyBytes = await request.read().fold<List<int>>(
        [],
        (previous, element) => previous..addAll(element),
      );

      if (bodyBytes.isNotEmpty) {
        return parseDocumentEventData(Uint8List.fromList(bodyBytes));
      }
    } catch (_) {
      // Protobuf parsing failed
    }
    return null;
  }

  /// Shared handler for single-snapshot triggers (created/deleted).
  ///
  /// When [withAuthContext] is `false`, [handler] is called with a
  /// `FirestoreEvent<EmulatorDocumentSnapshot?>`.
  /// When `true`, it is called with a
  /// `FirestoreAuthEvent<EmulatorDocumentSnapshot?>`.
  void _registerDocumentHandler({
    required String methodName,
    required String document,
    required bool Function(String) validateEventType,
    required bool withAuthContext,
    required Function handler,
  }) {
    final functionName = _documentToFunctionName(methodName, document);

    firebase.registerFunction(functionName, (request) async {
      try {
        final isBinaryMode = request.headers.containsKey('ce-type');

        if (isBinaryMode) {
          final ceType = request.headers['ce-type'];

          if (ceType != null && !validateEventType(ceType)) {
            return Response(
              400,
              body: 'Invalid event type for Firestore $methodName: $ceType',
            );
          }

          final headers = _extractHeaders(request);
          if (headers == null) {
            return Response(400, body: 'Missing required CloudEvent headers');
          }

          final params = _extractParams(document, headers.documentPath);

          final parsed = await _parseBody(request);
          final snapshotKey =
              (methodName == 'onDocumentDeleted' ||
                  methodName == 'onDocumentDeletedWithAuthContext')
              ? 'old_value'
              : 'value';
          final snapshot = parsed?[snapshotKey];

          if (withAuthContext) {
            final event = FirestoreAuthEvent<EmulatorDocumentSnapshot?>(
              data: snapshot,
              id: headers.id,
              source: headers.source,
              specversion: '1.0',
              subject: headers.subject,
              time: DateTime.parse(headers.time),
              type: headers.type,
              location: 'us-central1',
              project: _extractProject(headers.source),
              database: headers.database,
              namespace: headers.namespace,
              document: headers.documentPath,
              params: params,
              authType: AuthType.fromString(headers.authType ?? 'unknown'),
              authId: headers.authId,
            );

            await (handler
                as Future<void> Function(
                  FirestoreAuthEvent<EmulatorDocumentSnapshot?>,
                ))(event);
          } else {
            final event = FirestoreEvent<EmulatorDocumentSnapshot?>(
              data: snapshot,
              id: headers.id,
              source: headers.source,
              specversion: '1.0',
              subject: headers.subject,
              time: DateTime.parse(headers.time),
              type: headers.type,
              location: 'us-central1',
              project: _extractProject(headers.source),
              database: headers.database,
              namespace: headers.namespace,
              document: headers.documentPath,
              params: params,
            );

            await (handler
                as Future<void> Function(
                  FirestoreEvent<EmulatorDocumentSnapshot?>,
                ))(event);
          }

          return Response.ok('');
        } else {
          // Structured content mode: full CloudEvent in JSON body
          // Only supported for onDocumentCreated variants
          if (methodName == 'onDocumentCreated' ||
              methodName == 'onDocumentCreatedWithAuthContext') {
            final json = await parseAndValidateCloudEvent(request);

            if (!validateEventType(json['type'] as String)) {
              return Response(
                400,
                body:
                    'Invalid event type for Firestore $methodName: ${json['type']}',
              );
            }

            if (withAuthContext) {
              final event = FirestoreAuthEvent<EmulatorDocumentSnapshot?>(
                id: json['id'] as String,
                source: json['source'] as String,
                specversion: json['specversion'] as String,
                subject: json['subject'] as String?,
                time: DateTime.parse(json['time'] as String),
                type: json['type'] as String,
                location: json['location'] as String? ?? 'us-central1',
                project: 'unknown',
                database: '(default)',
                namespace: '(default)',
                document: '',
                params: {},
                authType: AuthType.fromString(
                  json['authtype'] as String? ?? 'unknown',
                ),
                authId: json['authid'] as String?,
              );

              await (handler
                  as Future<void> Function(
                    FirestoreAuthEvent<EmulatorDocumentSnapshot?>,
                  ))(event);
            } else {
              final event = FirestoreEvent<EmulatorDocumentSnapshot?>.fromJson(
                json,
                (data) {
                  // TODO: Parse protobuf data from structured CloudEvent
                  return null;
                },
              );

              await (handler
                  as Future<void> Function(
                    FirestoreEvent<EmulatorDocumentSnapshot?>,
                  ))(event);
            }

            return Response.ok('');
          }

          return Response(
            501,
            body:
                'Structured CloudEvent mode not yet supported for $methodName',
          );
        }
      } on FormatException catch (e) {
        return Response(400, body: 'Invalid CloudEvent: ${e.message}');
      }
    }, documentPattern: document);
  }

  /// Shared handler for change triggers (updated/written).
  ///
  /// When [withAuthContext] is `false`, [handler] is called with a
  /// `FirestoreEvent<Change<EmulatorDocumentSnapshot>?>`.
  /// When `true`, it is called with a
  /// `FirestoreAuthEvent<Change<EmulatorDocumentSnapshot>?>`.
  void _registerChangeHandler({
    required String methodName,
    required String document,
    required bool Function(String) validateEventType,
    required bool withAuthContext,
    required Function handler,
  }) {
    final functionName = _documentToFunctionName(methodName, document);

    firebase.registerFunction(functionName, (request) async {
      final isBinaryMode = request.headers.containsKey('ce-type');

      if (isBinaryMode) {
        final ceType = request.headers['ce-type'];

        if (ceType != null && !validateEventType(ceType)) {
          return Response(
            400,
            body: 'Invalid event type for Firestore $methodName: $ceType',
          );
        }

        final headers = _extractHeaders(request);
        if (headers == null) {
          return Response(400, body: 'Missing required CloudEvent headers');
        }

        final params = _extractParams(document, headers.documentPath);

        final parsed = await _parseBody(request);
        final beforeSnapshot = parsed?['old_value'];
        final afterSnapshot = parsed?['value'];

        final change = Change<EmulatorDocumentSnapshot>(
          before: beforeSnapshot,
          after: afterSnapshot,
        );

        if (withAuthContext) {
          final event = FirestoreAuthEvent<Change<EmulatorDocumentSnapshot>?>(
            data: change,
            id: headers.id,
            source: headers.source,
            specversion: '1.0',
            subject: headers.subject,
            time: DateTime.parse(headers.time),
            type: headers.type,
            location: 'us-central1',
            project: _extractProject(headers.source),
            database: headers.database,
            namespace: headers.namespace,
            document: headers.documentPath,
            params: params,
            authType: AuthType.fromString(headers.authType ?? 'unknown'),
            authId: headers.authId,
          );

          await (handler
              as Future<void> Function(
                FirestoreAuthEvent<Change<EmulatorDocumentSnapshot>?>,
              ))(event);
        } else {
          final event = FirestoreEvent<Change<EmulatorDocumentSnapshot>?>(
            data: change,
            id: headers.id,
            source: headers.source,
            specversion: '1.0',
            subject: headers.subject,
            time: DateTime.parse(headers.time),
            type: headers.type,
            location: 'us-central1',
            project: _extractProject(headers.source),
            database: headers.database,
            namespace: headers.namespace,
            document: headers.documentPath,
            params: params,
          );

          await (handler
              as Future<void> Function(
                FirestoreEvent<Change<EmulatorDocumentSnapshot>?>,
              ))(event);
        }

        return Response.ok('');
      } else {
        return Response(
          501,
          body: 'Structured CloudEvent mode not yet supported for $methodName',
        );
      }
    }, documentPattern: document);
  }

  /// Converts a document path to a function name.
  ///
  /// Examples:
  /// - 'users/{userId}' -> 'onDocumentCreated_users_userId'
  /// - 'users/user123' -> 'onDocumentCreated_users_user123'
  String _documentToFunctionName(String eventType, String documentPath) {
    // Remove leading/trailing slashes
    final cleaned = documentPath.replaceAll(RegExp(r'^/+|/+$'), '');

    // Replace path separators and wildcards with underscores
    final sanitized = cleaned
        .replaceAll('/', '_')
        .replaceAll('{', '')
        .replaceAll('}', '')
        .replaceAll('-', '');

    return '${eventType}_$sanitized';
  }

  /// Checks if the CloudEvent type is a Firestore document created event.
  /// Accepts both the base type and the `.withAuthContext` variant.
  bool _isFirestoreCreatedEvent(String type) =>
      type == 'google.cloud.firestore.document.v1.created' ||
      type == 'google.cloud.firestore.document.v1.created.withAuthContext';

  /// Checks if the CloudEvent type is a Firestore document updated event.
  /// Accepts both the base type and the `.withAuthContext` variant.
  bool _isFirestoreUpdatedEvent(String type) =>
      type == 'google.cloud.firestore.document.v1.updated' ||
      type == 'google.cloud.firestore.document.v1.updated.withAuthContext';

  /// Checks if the CloudEvent type is a Firestore document deleted event.
  /// Accepts both the base type and the `.withAuthContext` variant.
  bool _isFirestoreDeletedEvent(String type) =>
      type == 'google.cloud.firestore.document.v1.deleted' ||
      type == 'google.cloud.firestore.document.v1.deleted.withAuthContext';

  /// Checks if the CloudEvent type is a Firestore document written event.
  /// Accepts both the base type and the `.withAuthContext` variant.
  bool _isFirestoreWrittenEvent(String type) =>
      type == 'google.cloud.firestore.document.v1.written' ||
      type == 'google.cloud.firestore.document.v1.written.withAuthContext';

  /// Extracts path parameters from a document path by matching against a pattern.
  ///
  /// Example:
  /// - pattern: 'users/{userId}'
  /// - documentPath: 'users/abc123'
  /// - returns: {'userId': 'abc123'}
  Map<String, String> _extractParams(String pattern, String documentPath) {
    final params = <String, String>{};
    final patternParts = pattern.split('/');
    final documentParts = documentPath.split('/');

    if (patternParts.length != documentParts.length) {
      return params;
    }

    for (var i = 0; i < patternParts.length; i++) {
      final patternPart = patternParts[i];
      final documentPart = documentParts[i];

      // Extract parameter name from wildcards like {userId}
      if (patternPart.startsWith('{') && patternPart.endsWith('}')) {
        final paramName = patternPart.substring(1, patternPart.length - 1);
        params[paramName] = documentPart;
      }
    }

    return params;
  }

  /// Extracts the project ID from a CloudEvent source.
  ///
  /// Source format: //firestore.googleapis.com/projects/{project}/databases/{database}/...
  /// Note: Source may have nested paths like projects/projects/demo-test
  String _extractProject(String source) {
    final uri = Uri.parse(source.replaceFirst('//', 'https://'));
    final pathSegments = uri.pathSegments;

    // Find LAST 'projects' segment and return the next one
    // This handles cases like: projects/projects/demo-test
    var projectIndex = -1;
    for (var i = pathSegments.length - 1; i >= 0; i--) {
      if (pathSegments[i] == 'projects' && i + 1 < pathSegments.length) {
        projectIndex = i;
        break;
      }
    }

    if (projectIndex != -1) {
      return pathSegments[projectIndex + 1];
    }

    return 'unknown-project';
  }
}
