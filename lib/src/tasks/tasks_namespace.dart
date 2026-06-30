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
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart';

import 'package:stack_trace/stack_trace.dart' show Trace;

import '../../logger.dart' as logger;
import '../firebase.dart';
import 'options.dart';
import 'task_request.dart';

/// Task queue triggers namespace.
///
/// Provides methods to define task queue-triggered Cloud Functions
/// that handle tasks dispatched via Google Cloud Tasks.
class TasksNamespace extends FunctionsNamespace {
  /// Creates a tasks namespace.
  const TasksNamespace(super.firebase);

  /// Creates a function triggered by tasks dispatched to a Google Cloud Tasks queue.
  ///
  /// The handler receives a [TaskRequest] containing the task data and context.
  ///
  /// Example:
  /// ```dart
  /// firebase.tasks.onTaskDispatched(
  ///   name: 'processOrder',
  ///   (request) async {
  ///     final data = request.data as Map<String, dynamic>;
  ///     print('Processing order: ${data['orderId']}');
  ///     print('Task ID: ${request.id}');
  ///     print('Retry count: ${request.retryCount}');
  ///   },
  /// );
  /// ```
  void onTaskDispatched(
    Future<void> Function(TaskRequest<dynamic> request) handler, {
    // ignore: experimental_member_use
    @mustBeConst required String name,
    // ignore: experimental_member_use
    @mustBeConst TaskQueueOptions? options = const TaskQueueOptions(),
  }) {
    firebase.registerFunction(name, (request) async {
      try {
        // Parse request body
        final bodyString = await request.readAsString();
        final body = bodyString.isNotEmpty
            ? jsonDecode(bodyString) as Map<String, dynamic>
            : <String, dynamic>{};

        // Extract task context from Cloud Tasks headers
        final headers = request.headers;
        final queueName = headers['x-cloudtasks-queuename'] ?? '';
        final taskId = headers['x-cloudtasks-taskname'] ?? '';
        final retryCount =
            int.tryParse(headers['x-cloudtasks-taskretrycount'] ?? '') ?? 0;
        final executionCount =
            int.tryParse(headers['x-cloudtasks-taskexecutioncount'] ?? '') ?? 0;
        final scheduledTime = headers['x-cloudtasks-tasketa'] ?? '';
        final previousResponse = int.tryParse(
          headers['x-cloudtasks-taskpreviousresponse'] ?? '',
        );
        final retryReason = headers['x-cloudtasks-taskretryreason'];

        // Extract auth data if present
        TaskAuthData? auth;
        final authHeader = headers['authorization'] ?? '';
        final tokenMatch = RegExp(r'^Bearer (.*)$').firstMatch(authHeader);
        if (tokenMatch != null) {
          final token = tokenMatch.group(1)!;
          // Decode JWT payload (we skip verification since task queue
          // functions are guarded by IAM)
          final decoded = _unsafeDecodeToken(token);
          if (decoded != null) {
            auth = TaskAuthData(
              uid: decoded['uid'] as String? ?? decoded['sub'] as String? ?? '',
              token: DecodedIdToken(
                aud: decoded['aud'] as String? ?? '',
                authTime: DateTime.fromMillisecondsSinceEpoch(
                  ((decoded['auth_time'] as num?)?.toInt() ?? 0) * 1000,
                ),
                exp: (decoded['exp'] as num?)?.toInt() ?? 0,
                iat: (decoded['iat'] as num?)?.toInt() ?? 0,
                iss: decoded['iss'] as String? ?? '',
                sub: decoded['sub'] as String? ?? '',
                uid:
                    decoded['uid'] as String? ??
                    decoded['sub'] as String? ??
                    '',
                email: decoded['email'] as String?,
                emailVerified: decoded['email_verified'] as bool?,
                phoneNumber: decoded['phone_number'] as String?,
                picture: decoded['picture'] as String?,
              ),
            );
          }
        }

        // Build the task request
        final taskRequest = TaskRequest<dynamic>(
          request,
          body['data'],
          queueName: queueName,
          id: taskId,
          retryCount: retryCount,
          executionCount: executionCount,
          scheduledTime: scheduledTime,
          auth: auth,
          previousResponse: previousResponse,
          retryReason: retryReason,
        );

        // Execute handler
        await handler(taskRequest);

        // Return 204 No Content (matching Node.js behavior)
        return Response(204);
      } catch (e, stackTrace) {
        logger.error('$e\n${Trace.from(stackTrace).terse}');
        return Response(
          500,
          body: jsonEncode({
            'error': {'status': 'INTERNAL', 'message': 'INTERNAL'},
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }
    });
  }

  /// Unsafely decodes a JWT token without verification.
  ///
  /// Task queue functions are guarded by IAM, so we skip verification.
  Map<String, dynamic>? _unsafeDecodeToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      // Decode the payload (second part)
      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      return jsonDecode(decoded) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
