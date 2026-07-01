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

/// Billing alerts sub-namespace.
///
/// Provides methods to handle billing-specific alerts.
class BillingNamespace {
  const BillingNamespace(this._firebase);

  final Firebase _firebase;

  /// Handles billing plan update alerts.
  void onPlanUpdatePublished(
    FutureOr<void> Function(AlertEvent<PlanUpdatePayload> event) handler, {
    // ignore: experimental_member_use
    @mustBeConst AlertOptions? options = const AlertOptions(),
  }) {
    _registerBillingHandler<PlanUpdatePayload>(
      const BillingPlanUpdate(),
      handler,
      PlanUpdatePayload.fromJson,
      options,
    );
  }

  /// Handles automated billing plan update alerts.
  void onPlanAutomatedUpdatePublished(
    FutureOr<void> Function(AlertEvent<PlanAutomatedUpdatePayload> event)
    handler, {
    // ignore: experimental_member_use
    @mustBeConst AlertOptions? options = const AlertOptions(),
  }) {
    _registerBillingHandler<PlanAutomatedUpdatePayload>(
      const BillingPlanAutomatedUpdate(),
      handler,
      PlanAutomatedUpdatePayload.fromJson,
      options,
    );
  }

  void _registerBillingHandler<T extends Object>(
    BillingAlertType alertType,
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
