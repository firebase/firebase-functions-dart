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

import 'package:google_cloud_logging/google_cloud_logging.dart';

const _logger = StructuredLogger();

/// Logs messages with the given severity.
void write(
  LogSeverity severity,
  String message, [
  Map<String, dynamic> payload = const {},
  StackTrace? stackTrace,
]) {
  final copy = {...payload};
  if (message.isNotEmpty) {
    copy['message'] = message;
  }
  _logger.log(copy, severity, stackTrace: stackTrace);
}

/// Logs [message] with [LogSeverity.debug] severity.
///
/// Example:
/// ```dart
/// logger.debug(
///   'Database query executed',
///   {'query': 'SELECT * FROM users', 'durationMs': 42},
/// );
/// ```
void debug(
  String message, [
  Map<String, dynamic> payload = const {},
  StackTrace? stackTrace,
]) => write(LogSeverity.debug, message, payload, stackTrace);

/// Logs [message] with [LogSeverity.info] severity.
///
/// Example:
/// ```dart
/// logger.info(
///   'User signed in successfully',
///   {'provider': 'google.com'},
/// );
/// ```
void info(
  String message, [
  Map<String, dynamic> payload = const {},
  StackTrace? stackTrace,
]) => write(LogSeverity.info, message, payload, stackTrace);

/// Logs [message] with [LogSeverity.info] severity.
///
/// Example:
/// ```dart
/// logger.log('Request received');
/// ```
void log(
  String message, [
  Map<String, dynamic> payload = const {},
  StackTrace? stackTrace,
]) => write(LogSeverity.info, message, payload, stackTrace);

/// Logs [message] with [LogSeverity.warning] severity.
///
/// Example:
/// ```dart
/// logger.warning(
///   'Slow network request detected',
///   {'url': 'https://api.example.com/data', 'latencyMs': 1500},
/// );
/// ```
void warning(
  String message, [
  Map<String, dynamic> payload = const {},
  StackTrace? stackTrace,
]) => write(LogSeverity.warning, message, payload, stackTrace);

/// Logs [message] with [LogSeverity.error] severity.
///
/// Example:
/// ```dart
/// try {
///   throw Exception('Database connection failed');
/// } catch (e, stackTrace) {
///   logger.error(
///     'Failed to process transaction',
///     {'transactionId': 'tx-999'},
///     stackTrace,
///   );
/// }
/// ```
void error(
  String message, [
  Map<String, dynamic> payload = const {},
  StackTrace? stackTrace,
]) => write(LogSeverity.error, message, payload, stackTrace);
