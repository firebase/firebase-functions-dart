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

import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart';

import '../common/options.dart';
import '../common/utilities.dart';
import '../firebase.dart';
import 'auth.dart';
import 'callable.dart';
import 'error.dart';
import 'options.dart';

/// HTTPS triggers namespace.
///
/// Provides methods to define HTTP-triggered Cloud Functions.
class HttpsNamespace extends FunctionsNamespace {
  const HttpsNamespace(super.firebase);

  /// Creates an HTTPS function that handles raw HTTP requests.
  ///
  /// The handler receives a Shelf [Request] and must return a Shelf [Response].
  ///
  /// Example:
  /// ```dart
  /// firebase.https.onRequest(
  ///   name: 'hello',
  ///   (request) async {
  ///     return Response.ok('Hello World!');
  ///   },
  /// );
  /// ```
  void onRequest(
    Future<Response> Function(Request request) handler, {
    // ignore: experimental_member_use
    @mustBeConst required String name,
    // ignore: experimental_member_use
    @mustBeConst HttpsOptions? options = const HttpsOptions(),
  }) {
    firebase.registerFunction(
      name,
      (request) async {
        try {
          return await handler(request);
        } on HttpsError catch (e) {
          return e.toShelfResponse();
        } catch (e, stackTrace) {
          return logInternalError(e, stackTrace).toShelfResponse();
        }
      },
      external: true,
      allowedOrigins: options?.cors?.runtimeValue(),
    );
  }

  /// Creates an HTTPS callable function (untyped data).
  ///
  /// Callable functions provide a simple RPC interface with automatic
  /// request/response handling and Firebase Auth integration.
  ///
  /// Example:
  /// ```dart
  /// firebase.https.onCall(
  ///   name: 'greet',
  ///   (request, response) async {
  ///     final name = request.data['name'] as String;
  ///     return CallableResult({'message': 'Hello $name!'});
  ///   },
  /// );
  /// ```
  void onCall<T extends Object>(
    Future<CallableResult<T>> Function(
      CallableRequest<Object?> request,
      CallableResponse<T> response,
    )
    handler, {
    // ignore: experimental_member_use
    @mustBeConst required String name,
    // ignore: experimental_member_use
    @mustBeConst CallableOptions? options = const CallableOptions(),
  }) {
    firebase.registerFunction(name, (request) async {
      final bodyString = await request.change().readAsString();
      Map<String, dynamic>? body;
      if (bodyString.isNotEmpty) {
        try {
          body = jsonDecode(bodyString) as Map<String, dynamic>;
        } catch (_) {
          // Invalid JSON - body stays null, validation will fail
        }
      }

      // Extract auth and app check tokens

      final tokens = await checkTokens(
        request.headers,
        adminApp: firebase.$env.skipTokenVerification
            ? null
            : firebase.adminApp,
      );

      // Check for invalid auth token
      if (tokens.result.auth == TokenStatus.invalid) {
        return UnauthenticatedError().toShelfResponse();
      }

      // Check for invalid or missing app check token if enforced
      final enforceAppCheck =
          options?.enforceAppCheck?.runtimeValue() ??
          getGlobalOptions().enforceAppCheck?.runtimeValue() ??
          false;
      if (tokens.result.app == TokenStatus.invalid) {
        if (enforceAppCheck) {
          return UnauthenticatedError().toShelfResponse();
        }
      }
      if (tokens.result.app == TokenStatus.missing && enforceAppCheck) {
        return UnauthenticatedError().toShelfResponse();
      }

      final callableRequest = CallableRequest(
        request,
        body?['data'],
        null,
        auth: tokens.authData,
        app: tokens.appCheckData,
      );

      return _handleCallable<Object?, T, CallableResult<T>>(
        request,
        callableRequest,
        body,
        options,
        handler,
        (result) => result.data,
        (result) => result.toResponse(),
      );
    }, allowedOrigins: options?.cors?.runtimeValue());
  }

  /// Creates an HTTPS callable function with typed data.
  ///
  /// Provides type-safe request/response handling with custom serialization.
  ///
  /// Example:
  /// ```dart
  /// class GreetRequest {
  ///   final String name;
  ///   GreetRequest(this.name);
  ///   factory GreetRequest.fromJson(Map<String, dynamic> json) =>
  ///       GreetRequest(json['name'] as String);
  /// }
  ///
  /// firebase.https.onCallWithData<GreetRequest, String>(
  ///   name: 'greetTyped',
  ///   fromJson: GreetRequest.fromJson,
  ///   (request, response) async {
  ///     return 'Hello ${request.data.name}!';
  ///   },
  /// );
  /// ```
  void onCallWithData<Input extends Object, Output extends Object>(
    Future<Output> Function(
      CallableRequest<Input> request,
      CallableResponse<Output> response,
    )
    handler, {
    required Input Function(Map<String, dynamic>) fromJson,
    // ignore: experimental_member_use
    @mustBeConst required String name,
    // ignore: experimental_member_use
    @mustBeConst CallableOptions? options = const CallableOptions(),
  }) {
    firebase.registerFunction(name, (request) async {
      final body = await request.json as Map<String, dynamic>?;

      // Extract auth and app check tokens

      final tokens = await checkTokens(
        request.headers,
        adminApp: firebase.$env.skipTokenVerification
            ? null
            : firebase.adminApp,
      );

      // Check for invalid auth token
      if (tokens.result.auth == TokenStatus.invalid) {
        return UnauthenticatedError().toShelfResponse();
      }

      // Check for invalid or missing app check token if enforced
      final enforceAppCheck =
          options?.enforceAppCheck?.runtimeValue() ??
          getGlobalOptions().enforceAppCheck?.runtimeValue() ??
          false;
      if (tokens.result.app == TokenStatus.invalid) {
        if (enforceAppCheck) {
          return UnauthenticatedError().toShelfResponse();
        }
      }
      if (tokens.result.app == TokenStatus.missing && enforceAppCheck) {
        return UnauthenticatedError().toShelfResponse();
      }

      final callableRequest = CallableRequest<Input>(
        request,
        body?['data'],
        fromJson,
        auth: tokens.authData,
        app: tokens.appCheckData,
      );

      return _handleCallable<Input, Output, Output>(
        request,
        callableRequest,
        body,
        options,
        handler,
        (result) => result,
        (result) => Response.ok(
          jsonEncode({'result': result}),
          headers: {'Content-Type': 'application/json'},
        ),
      );
    }, allowedOrigins: options?.cors?.runtimeValue());
  }

  /// Internal handler for callable functions.
  ///
  /// Handles both streaming and non-streaming responses, error handling,
  /// and request validation.
  Future<Response> _handleCallable<
    Req extends Object?,
    StreamType extends Object,
    Res extends Object
  >(
    Request request,
    CallableRequest<Req> callableRequest,
    Map<String, dynamic>? body,
    CallableOptions? options,
    Future<Res> Function(
      CallableRequest<Req> request,
      CallableResponse<StreamType> response,
    )
    handler,
    dynamic Function(Res result) extractResultData,
    Response Function(Res result) createNonStreamingResponse,
  ) async {
    // Validate request - pass empty map if body is null to avoid double-read
    if (!await request.isValidRequest(body ?? {})) {
      return InvalidArgumentError('Invalid callable request').toShelfResponse();
    }

    final heartbeatSeconds = options?.heartBeatIntervalSeconds?.runtimeValue();
    final callableResponse = CallableResponse<StreamType>(
      acceptsStreaming: callableRequest.acceptsStreaming,
      heartbeatSeconds: heartbeatSeconds,
    );

    try {
      // Initialize streaming if requested
      if (callableRequest.acceptsStreaming) {
        callableResponse.initializeStreaming();
      }

      // Execute handler
      final result = await handler(callableRequest, callableResponse);

      // Handle streaming response
      if (callableRequest.acceptsStreaming && !callableResponse.aborted) {
        final finalResult = {'result': extractResultData(result)};
        callableResponse.writeSSE(finalResult);
        if (!callableResponse.isUsingResponseStream) {
          unawaited(callableResponse.closeStream());
        }
        return callableResponse.streamingResponse!;
      }

      // Non-streaming response
      return createNonStreamingResponse(result);
    } on HttpsError catch (e) {
      // Handle HttpsError - use SSE format if streaming
      if (callableRequest.acceptsStreaming && !callableResponse.aborted) {
        callableResponse.writeSSE(e.toErrorResponse());
        unawaited(callableResponse.closeStream());
        return callableResponse.streamingResponse!;
      }

      return e.toShelfResponse();
    } catch (e, stackTrace) {
      // Unexpected error - don't expose details to client
      final error = logInternalError(e, stackTrace);

      if (callableRequest.acceptsStreaming && !callableResponse.aborted) {
        callableResponse.writeSSE(error.toErrorResponse());
        unawaited(callableResponse.closeStream());
        return callableResponse.streamingResponse!;
      }

      return error.toShelfResponse();
    }
  }
}
