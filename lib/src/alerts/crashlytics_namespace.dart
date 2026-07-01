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
import 'alert_event.dart';
import 'alert_type.dart';
import 'options.dart';

/// Crashlytics alerts sub-namespace.
///
/// Provides methods to handle Crashlytics-specific alerts.
class CrashlyticsNamespace {
  const CrashlyticsNamespace(this._firebase);

  final Firebase _firebase;

  /// Handles new fatal issue alerts from Crashlytics.
  void onNewFatalIssuePublished(
    FutureOr<void> Function(AlertEvent<NewFatalIssuePayload> event) handler, {
    // ignore: experimental_member_use
    @mustBeConst AlertOptions? options = const AlertOptions(),
  }) {
    _registerCrashlyticsHandler<NewFatalIssuePayload>(
      const CrashlyticsNewFatalIssue(),
      handler,
      NewFatalIssuePayload.fromJson,
      options,
    );
  }

  /// Handles new non-fatal issue alerts from Crashlytics.
  void onNewNonfatalIssuePublished(
    FutureOr<void> Function(AlertEvent<NewNonfatalIssuePayload> event)
    handler, {
    // ignore: experimental_member_use
    @mustBeConst AlertOptions? options = const AlertOptions(),
  }) {
    _registerCrashlyticsHandler<NewNonfatalIssuePayload>(
      const CrashlyticsNewNonfatalIssue(),
      handler,
      NewNonfatalIssuePayload.fromJson,
      options,
    );
  }

  /// Handles regression alerts from Crashlytics.
  void onRegressionAlertPublished(
    FutureOr<void> Function(AlertEvent<RegressionAlertPayload> event) handler, {
    // ignore: experimental_member_use
    @mustBeConst AlertOptions? options = const AlertOptions(),
  }) {
    _registerCrashlyticsHandler<RegressionAlertPayload>(
      const CrashlyticsRegression(),
      handler,
      RegressionAlertPayload.fromJson,
      options,
    );
  }

  /// Handles stability digest alerts from Crashlytics.
  void onStabilityDigestPublished(
    FutureOr<void> Function(AlertEvent<StabilityDigestPayload> event) handler, {
    // ignore: experimental_member_use
    @mustBeConst AlertOptions? options = const AlertOptions(),
  }) {
    _registerCrashlyticsHandler<StabilityDigestPayload>(
      const CrashlyticsStabilityDigest(),
      handler,
      StabilityDigestPayload.fromJson,
      options,
    );
  }

  /// Handles velocity alerts from Crashlytics.
  void onVelocityAlertPublished(
    FutureOr<void> Function(AlertEvent<VelocityAlertPayload> event) handler, {
    // ignore: experimental_member_use
    @mustBeConst AlertOptions? options = const AlertOptions(),
  }) {
    _registerCrashlyticsHandler<VelocityAlertPayload>(
      const CrashlyticsVelocity(),
      handler,
      VelocityAlertPayload.fromJson,
      options,
    );
  }

  /// Handles new ANR (Application Not Responding) issue alerts from Crashlytics.
  void onNewAnrIssuePublished(
    FutureOr<void> Function(AlertEvent<NewAnrIssuePayload> event) handler, {
    // ignore: experimental_member_use
    @mustBeConst AlertOptions? options = const AlertOptions(),
  }) {
    _registerCrashlyticsHandler<NewAnrIssuePayload>(
      const CrashlyticsNewAnrIssue(),
      handler,
      NewAnrIssuePayload.fromJson,
      options,
    );
  }

  void _registerCrashlyticsHandler<T extends Object>(
    CrashlyticsAlertType alertType,
    FutureOr<void> Function(AlertEvent<T> event) handler,
    T Function(Map<String, dynamic>) payloadDecoder,
    AlertOptions? options,
  ) {
    final functionName = _alertTypeToFunctionName(alertType.value);

    _firebase.registerFunction(functionName, (request) async {
      try {
        final json = await parseAndValidateCloudEvent(request);

        if (!_isAlertEvent(json['type'] as String)) {
          return Response(
            400,
            body: 'Invalid event type for alerts: ${json['type']}',
          );
        }

        final event = AlertEvent<T>.fromJson(json, payloadDecoder);
        await handler(event);
        return Response.ok('');
      } on FormatException catch (e) {
        return Response(400, body: 'Invalid CloudEvent: ${e.message}');
      }
    });
  }

  String _alertTypeToFunctionName(String alertType) {
    final sanitized = alertType.replaceAll('.', '_').replaceAll('-', '');
    return 'onAlertPublished_$sanitized';
  }

  bool _isAlertEvent(String type) => type == alertEventType;
}
