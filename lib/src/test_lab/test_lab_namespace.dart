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
import 'test_matrix_completed_data.dart';

/// Firebase Test Lab triggers namespace.
///
/// Provides methods to define Test Lab-triggered Cloud Functions.
class TestLabNamespace extends FunctionsNamespace {
  const TestLabNamespace(super.firebase);

  /// Creates a function triggered when a Firebase test matrix completes.
  ///
  /// The handler receives a [CloudEvent] containing [TestMatrixCompletedData].
  ///
  /// Example:
  /// ```dart
  /// firebase.testLab.onTestMatrixCompleted(
  ///   (event) async {
  ///     final data = event.data;
  ///     print('Test matrix ${data?.testMatrixId} completed');
  ///     print('State: ${data?.state.value}');
  ///     print('Outcome: ${data?.outcomeSummary.value}');
  ///   },
  /// );
  /// ```
  void onTestMatrixCompleted(
    Future<void> Function(CloudEvent<TestMatrixCompletedData> event) handler, {
    // ignore: experimental_member_use
    @mustBeConst TestLabOptions? options = const TestLabOptions(),
  }) {
    firebase.registerFunction(_functionName, (request) async {
      try {
        final json = await parseAndValidateCloudEvent(request);

        final eventType = json['type'] as String;
        if (eventType != _eventType) {
          return Response(
            400,
            body: 'Invalid event type for Test Lab: $eventType',
          );
        }

        final event = CloudEvent<TestMatrixCompletedData>.fromJson(
          json,
          TestMatrixCompletedData.fromJson,
        );

        await handler(event);

        return Response.ok('');
      } on FormatException catch (e) {
        return Response(400, body: 'Invalid CloudEvent: ${e.message}');
      }
    });
  }

  static const _functionName = 'onTestMatrixCompleted';
  static const _eventType = 'google.firebase.testlab.testMatrix.v1.completed';
}
