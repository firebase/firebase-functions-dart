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

void write(
  LogSeverity severity,
  String message, [
  Map<dynamic, dynamic> payload = const {},
  StackTrace? stackTrace,
]) {
  final copy = {...payload};
  if (message.isNotEmpty) {
    copy['message'] = message;
  }
  _logger.log(copy, severity, stackTrace: stackTrace);
}

void debug(
  String message, [
  Map<dynamic, dynamic> payload = const {},
  StackTrace? stackTrace,
]) => write(LogSeverity.debug, message, payload, stackTrace);

void info(
  String message, {
  Map<dynamic, dynamic> payload = const {},
  StackTrace? stackTrace,
}) => write(LogSeverity.info, message, payload, stackTrace);

void warning(
  String message, [
  Map<dynamic, dynamic> payload = const {},
  StackTrace? stackTrace,
]) => write(LogSeverity.warning, message, payload, stackTrace);

void error(
  String message, [
  Map<dynamic, dynamic> payload = const {},
  StackTrace? stackTrace,
]) => write(LogSeverity.error, message, payload, stackTrace);
