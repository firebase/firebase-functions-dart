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

import '../firebase.dart';
import 'options.dart';
import 'scheduled_event.dart';

/// Scheduler triggers namespace.
///
/// Provides methods to define scheduled Cloud Functions that run
/// on a cron schedule via Cloud Scheduler.
class SchedulerNamespace extends FunctionsNamespace {
  /// Creates a scheduler namespace.
  const SchedulerNamespace(super.firebase);

  /// Creates a function that runs on a schedule.
  ///
  /// The function is triggered by Cloud Scheduler at the specified interval.
  ///
  /// The [schedule] parameter accepts either:
  /// - Unix Crontab syntax: `'0 5 * * *'` (5:00 AM daily)
  /// - App Engine cron syntax: `'every 1 hours'`
  ///
  /// Example:
  /// ```dart
  /// // Run every day at midnight UTC
  /// firebase.scheduler.onSchedule(
  ///   schedule: '0 0 * * *',
  ///   (event) async {
  ///     print('Running scheduled job: ${event.jobName}');
  ///     print('Scheduled for: ${event.scheduleTime}');
  ///   },
  /// );
  ///
  /// // Run every 5 minutes with retry config
  /// firebase.scheduler.onSchedule(
  ///   schedule: '*/5 * * * *',
  ///   options: ScheduleOptions(
  ///     timeZone: TimeZone('America/New_York'),
  ///     retryConfig: RetryConfig(
  ///       retryCount: RetryCount(3),
  ///       maxRetrySeconds: MaxRetrySeconds(60),
  ///     ),
  ///   ),
  ///   (event) async {
  ///     // Your scheduled task
  ///   },
  /// );
  /// ```
  ///
  /// ## Cron Syntax
  ///
  /// The cron expression has 5 fields:
  /// ```
  /// ┌───────────── minute (0 - 59)
  /// │ ┌───────────── hour (0 - 23)
  /// │ │ ┌───────────── day of month (1 - 31)
  /// │ │ │ ┌───────────── month (1 - 12)
  /// │ │ │ │ ┌───────────── day of week (0 - 6) (Sunday = 0)
  /// │ │ │ │ │
  /// * * * * *
  /// ```
  ///
  /// Common examples:
  /// - `'0 0 * * *'` - Every day at midnight
  /// - `'*/5 * * * *'` - Every 5 minutes
  /// - `'0 */2 * * *'` - Every 2 hours
  /// - `'0 9 * * 1'` - Every Monday at 9:00 AM
  /// - `'0 0 1 * *'` - First day of every month at midnight
  void onSchedule(
    Future<void> Function(ScheduledEvent event) handler, {
    // ignore: experimental_member_use
    @mustBeConst required String schedule,
    // ignore: experimental_member_use
    @mustBeConst ScheduleOptions? options = const ScheduleOptions(),
  }) {
    // Generate function name from schedule
    final functionName = _scheduleToFunctionName(schedule);

    firebase.registerFunction(functionName, (request) async {
      // Extract event data from request headers
      final headers = _lowercaseHeaders(request.headers);
      final event = ScheduledEvent.fromHeaders(headers);

      // Execute handler
      await handler(event);

      // Return success (Cloud Scheduler expects 2xx response)
      return Response.ok('');
    });
  }

  /// Converts a schedule expression to a function name.
  ///
  /// Generates a unique, URL-safe function name from the schedule.
  ///
  /// Examples:
  /// - `'0 0 * * *'` -> `'onSchedule_0_0___'`
  /// - `'*/5 * * * *'` -> `'onSchedule_5____'`
  String _scheduleToFunctionName(String schedule) {
    // Sanitize the schedule to be URL-safe
    final sanitized = schedule
        .replaceAll(' ', '_')
        .replaceAll('*', '')
        .replaceAll('/', '')
        .replaceAll('-', '')
        .replaceAll(',', '');

    return 'onSchedule_$sanitized';
  }

  /// Converts header keys to lowercase for case-insensitive lookup.
  Map<String, String> _lowercaseHeaders(Map<String, dynamic> headers) {
    return headers.map(
      (key, value) => MapEntry(key.toLowerCase(), value.toString()),
    );
  }
}
