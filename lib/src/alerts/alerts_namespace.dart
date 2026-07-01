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
import 'app_distribution_namespace.dart';
import 'billing_namespace.dart';
import 'crashlytics_namespace.dart';
import 'options.dart';
import 'performance_namespace.dart';

/// Firebase Alerts namespace.
///
/// Provides methods to define Firebase Alert-triggered Cloud Functions.
///
/// Example:
/// ```dart
/// firebase.alerts.crashlytics.onNewFatalIssuePublished(
///   (event) async {
///     final issue = event.data.payload.issue;
///     print('New fatal issue: ${issue.title}');
///   },
/// );
/// ```
class AlertsNamespace extends FunctionsNamespace {
  const AlertsNamespace(super.firebase);

  /// Crashlytics alerts sub-namespace.
  CrashlyticsNamespace get crashlytics => CrashlyticsNamespace(firebase);

  /// Billing alerts sub-namespace.
  BillingNamespace get billing => BillingNamespace(firebase);

  /// App Distribution alerts sub-namespace.
  AppDistributionNamespace get appDistribution =>
      AppDistributionNamespace(firebase);

  /// Performance alerts sub-namespace.
  PerformanceNamespace get performance => PerformanceNamespace(firebase);

  /// Creates a function triggered by any Firebase Alert.
  ///
  /// This is a generic handler that can handle any alert type.
  /// For type-safe handling, use the specific sub-namespace methods
  /// like `crashlytics.onNewFatalIssuePublished`.
  ///
  /// The handler receives an [AlertEvent] containing the alert data.
  ///
  /// Example:
  /// ```dart
  /// firebase.alerts.onAlertPublished(
  ///   alertType: const CrashlyticsNewFatalIssue(),
  ///   (event) async {
  ///     print('Alert: ${event.alertType}');
  ///     print('App ID: ${event.appId}');
  ///   },
  /// );
  /// ```
  void onAlertPublished<T extends Object>(
    FutureOr<void> Function(AlertEvent<T> event) handler, {
    // ignore: experimental_member_use
    @mustBeConst required AlertType alertType,
    // ignore: experimental_member_use
    @mustBeConst required T Function(Map<String, dynamic>) fromJson,
    // ignore: experimental_member_use
    @mustBeConst AlertOptions? options = const AlertOptions(),
  }) {
    final functionName = _alertTypeToFunctionName(alertType.value);

    firebase.registerFunction(functionName, (request) async {
      try {
        final json = await parseAndValidateCloudEvent(request);

        if (!_isAlertEvent(json['type'] as String)) {
          return Response(
            400,
            body: 'Invalid event type for alerts: ${json['type']}',
          );
        }

        final event = AlertEvent<T>.fromJson(json, fromJson);
        await handler(event);
        return Response.ok('');
      } on FormatException catch (e) {
        return Response(400, body: 'Invalid CloudEvent: ${e.message}');
      }
    });
  }

  /// Converts an alert type value to a function name.
  String _alertTypeToFunctionName(String alertType) {
    final sanitized = alertType.replaceAll('.', '_').replaceAll('-', '');
    return 'onAlertPublished_$sanitized';
  }

  /// Checks if the event type is a Firebase Alert event.
  bool _isAlertEvent(String type) => type == alertEventType;
}
