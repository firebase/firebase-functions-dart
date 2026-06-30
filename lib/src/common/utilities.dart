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

import 'dart:convert';

import 'package:shelf/shelf.dart' show Request, Response;
import 'package:stack_trace/stack_trace.dart' show Trace;

import '../../logger.dart' as logger;
import '../https/error.dart';

Future<Map<String, dynamic>> readAsJsonMap(Request request) async {
  final decoded = await _converter.bind(request.read()).first;
  return switch (decoded) {
    final Map<String, dynamic> m => m,
    _ => throw const FormatException('CloudEvent body must be a JSON object'),
  };
}

final _converter = const Utf8Decoder().fuse(const JsonDecoder());

extension HttpErrorExtension on HttpsError {
  Response toShelfResponse() => Response(
    httpStatusCode,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(toErrorResponse()),
  );
}

/// Logs an unexpected error with its stack trace and returns an [InternalError].
///
/// Use in HTTPS and callable function handlers where the response must be
/// a structured JSON error. The actual error details are only logged
/// server-side and never exposed to the client.
InternalError logInternalError(Object error, StackTrace stackTrace) {
  _logError(error, stackTrace);
  return InternalError();
}

/// Logs an unexpected error with its stack trace and returns a generic 500
/// response.
///
/// Use in event-triggered function handlers (Firestore, PubSub, Storage, etc.)
/// where the caller is the Cloud Functions infrastructure rather than an
/// end-user client.
Response logEventHandlerError(Object error, StackTrace stackTrace) {
  _logError(error, stackTrace);
  return Response.internalServerError();
}

/// Formats and logs an error with a terse, readable stack trace.
void _logError(Object error, StackTrace stackTrace) {
  final terse = Trace.from(stackTrace).terse;
  logger.error('$error\n$terse');
}
