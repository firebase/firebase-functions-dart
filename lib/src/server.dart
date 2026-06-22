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
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:stack_trace/stack_trace.dart' show Trace;

import 'common/cloud_run_id.dart';
import 'common/environment.dart';
import 'common/on_init.dart';
import 'firebase.dart';
import 'logger/logger.dart';

/// Callback type for the user's function registration code.
typedef FunctionsRunner = FutureOr<void> Function(Firebase firebase);

/// Runtime configuration options for [runFunctions].
class RunFunctionsOptions {
  const RunFunctionsOptions({this.poweredByHeader});

  /// Value for the `x-powered-by` response header.
  ///
  /// Defaults to `null`, which omits the header entirely. Pass a string to set
  /// a custom value. This applies to all responses, including
  /// internally-generated shelf error responses.
  final String? poweredByHeader;
}

/// Starts the Firebase Functions runtime.
///
/// This is the main entry point for a Firebase Functions application.
///
/// Example:
/// ```dart
/// void main(List<String> args) {
///   runFunctions((firebase) {
///     firebase.https.onRequest(
///       name: 'hello',
///       (request) async => Response.ok('Hello!'),
///     );
///   });
/// }
/// ```
@Deprecated('Use `runFunctions` instead.')
Future<void> fireUp(List<String> args, FunctionsRunner runner) =>
    runFunctions(runner);

/// Starts the Firebase Functions runtime.
///
/// This is the main entry point for a Firebase Functions application.
///
/// Example:
/// ```dart
/// void main(List<String> args) {
///   runFunctions((firebase) {
///     firebase.https.onRequest(
///       name: 'hello',
///       (request) async => Response.ok('Hello!'),
///     );
///   });
/// }
/// ```
Future<void> runFunctions(
  FunctionsRunner runner, {
  RunFunctionsOptions options = const RunFunctionsOptions(),
}) async {
  final firebase = createFirebaseInternal();
  final env = firebase.$env;
  final projectId = env.projectId;

  await runZoned(zoneValues: {projectIdZoneKey: projectId}, () async {
    // Run user's function registration code
    await runner(firebase);

    // Build request handler with middleware pipeline
    var middleware = const Pipeline().middleware;

    final env = firebase.$env;
    if (env.enableCors) {
      middleware = middleware.addMiddleware(_corsMiddleware);
    }

    // Build request handler with middleware pipeline
    final handler = middleware.addHandler((request) {
      final traceId = extractTraceId(request.headers[cloudTraceContextHeader]);

      if (traceId == null) {
        return _routeRequest(request, firebase, env);
      }

      return runZoned(zoneValues: {traceIdZoneKey: traceId}, () {
        return _routeRequest(request, firebase, env);
      });
    });

    // Start HTTP server
    await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      env.port,
      poweredByHeader: options.poweredByHeader,
    );
  });
}

/// Creates a shelf [Handler] for [firebase] without starting an HTTP server.
///
/// Use in tests to exercise the full routing pipeline without binding a port.
@visibleForTesting
Handler createTestHandler(Firebase firebase) =>
    (request) => _routeRequest(request, firebase, firebase.$env);

/// CORS middleware for emulator mode.
Handler _corsMiddleware(Handler innerHandler) => (request) {
  // Handle preflight OPTIONS requests
  if (request.method.toUpperCase() == 'OPTIONS') {
    return Response(204, headers: _corsAnyOriginHeaders);
  }

  return Future.sync(() => innerHandler(request)).then((response) {
    // Add CORS headers to all responses if enabled
    return response.change(headers: _corsAnyOriginHeaders);
  });
};

const _corsAnyOriginHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': '*',
  'Access-Control-Allow-Headers': '*',
};

Response _buildOptionsCorsResponse(
  Request request,
  List<String> allowedOrigins,
) => Response.ok('', headers: corsHeadersFor(request, allowedOrigins));

Response _applyCorsHeaders(
  Request request,
  Response response,
  List<String> allowedOrigins,
) => response.change(headers: corsHeadersFor(request, allowedOrigins));

@visibleForTesting
Map<String, String> corsHeadersFor(
  Request request,
  List<String> allowedOrigins,
) {
  if (allowedOrigins.contains('*')) {
    return _corsAnyOriginHeaders;
  }

  final origin = request.headers['origin'];
  if (origin != null && allowedOrigins.contains(origin)) {
    return {
      'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Methods': '*',
      'Access-Control-Allow-Headers': '*',
    };
  }

  return const {};
}

/// Routes incoming requests to the appropriate function handler.
FutureOr<Response> _routeRequest(
  Request request,
  Firebase firebase,
  FirebaseEnv env,
) {
  final functions = firebase.functions;
  final requestPath = request.url.path;

  // Handle special Node.js-compatible endpoints
  if (requestPath == '__/health') {
    // Health check endpoint (used by Firebase emulator)
    return Response.ok('OK');
  }

  if (requestPath == '__/quitquitquit') {
    // Graceful shutdown endpoint (used by Cloud Run)
    return _handleQuitQuitQuit(request);
  }

  if (requestPath == '__/functions.yaml' && env.functionsControlApi) {
    // Manifest endpoint for function discovery
    return _handleFunctionsManifest(request, firebase);
  }

  // FUNCTION_TARGET mode (production): Serve only the specified function
  // This matches Node.js behavior where each Cloud Run service runs one function
  final functionTarget = env.functionTarget;
  if (functionTarget != null && functionTarget.isNotEmpty) {
    return _routeToTargetFunction(request, firebase, env, functionTarget);
  }

  // Shared process mode (development): Route by path
  return _routeByPath(request, functions, requestPath);
}

/// Routes request to the function specified by FUNCTION_TARGET.
///
/// This matches Node.js production behavior where FUNCTION_TARGET is set
/// by Cloud Run to specify which function this process instance serves.
FutureOr<Response> _routeToTargetFunction(
  Request request,
  Firebase firebase,
  FirebaseEnv env,
  String functionTarget,
) async {
  final functions = firebase.functions;

  // Find the function with matching name
  final targetFunction = functions
      .where((f) => f.name == functionTarget)
      .firstOrNull;

  if (targetFunction == null) {
    return Response.notFound(
      'Function "$functionTarget" not found. '
      'Available functions: ${functions.map((f) => f.name).join(", ")}',
    );
  }

  // Note: FUNCTION_SIGNATURE_TYPE validation is skipped for Dart Cloud Run
  // deployments. All Dart functions (onRequest, onCall, event triggers) are
  // served via HTTP in a single process, so the signature type distinction
  // from the Node.js model does not apply here.

  // Validate HTTP method for event functions
  if (request.method.toUpperCase() == 'OPTIONS' &&
      targetFunction.allowedOrigins != null) {
    return _buildOptionsCorsResponse(request, targetFunction.allowedOrigins!);
  }

  if (!targetFunction.external && request.method.toUpperCase() != 'POST') {
    return Response(
      405,
      body: 'Event function "$functionTarget" only accepts POST requests',
      headers: {'Allow': 'POST'},
    );
  }

  final wrappedHandler = withInit(targetFunction.handler);
  final response = await wrappedHandler(request);
  if (targetFunction.allowedOrigins != null) {
    return _applyCorsHeaders(request, response, targetFunction.allowedOrigins!);
  }
  return response;
}

FutureOr<Response> _routeByPath(
  Request request,
  List<FirebaseFunctionDeclaration> functions,
  String requestPath,
) async {
  // Use a local variable for the potentially reconstructed request
  var currentRequest = request;

  // For POST requests, check if this is a CloudEvent first (binary or structured mode)
  // CloudEvents have all the routing info in headers, so check those before path parsing
  if (request.method.toUpperCase() == 'POST') {
    final (reconstructedRequest, matchedFunction) =
        await _tryMatchCloudEventFunction(request, functions);
    if (matchedFunction != null) {
      // Use the recreated request with the body since we consumed the original
      // Wrap with onInit to ensure initialization callback runs before first execution
      final wrappedHandler = withInit(matchedFunction.handler);
      return wrappedHandler(reconstructedRequest);
    }
    // Use the reconstructed request for further processing
    currentRequest = reconstructedRequest;
  }

  // Not a CloudEvent — route to a registered HTTPS function.
  //
  // The functions emulator always forwards to the Dart process with the path
  // stripped to /{functionName}[/{rest}], so parts[0] is the function name.
  // For direct calls that bypass the emulator, the format is
  // /{project}/{region}/{functionName}[/{rest}], so parts[2] is the function
  // name. We resolve the ambiguity by checking each registered function name
  // against the path segments rather than guessing from segment count.
  var normalPath = requestPath;
  if (normalPath.startsWith('/')) normalPath = normalPath.substring(1);
  if (normalPath.endsWith('/')) {
    normalPath = normalPath.substring(0, normalPath.length - 1);
  }
  final parts = normalPath.isEmpty ? <String>[] : normalPath.split('/');

  // X-Firebase-Function header is set by firebase-tools for hosting rewrites.
  final xFirebaseFunction = currentRequest.headers['x-firebase-function'];

  for (final function in functions) {
    String? originalPath;

    if (xFirebaseFunction != null) {
      // Header explicitly identifies the function; use it.
      if (function.name != xFirebaseFunction) continue;
      if (parts.isNotEmpty && parts[0] == function.name) {
        final rest = parts.sublist(1).join('/');
        originalPath = rest.isEmpty ? '/' : '/$rest';
      } else {
        originalPath = '/';
      }
    } else if (parts.isNotEmpty && parts[0] == function.name) {
      // /{functionName}[/{rest}] — emulator routing
      final rest = parts.sublist(1).join('/');
      originalPath = rest.isEmpty ? '/' : '/$rest';
    } else if (parts.length >= 3 && parts[2] == function.name) {
      // /{project}/{region}/{functionName}[/{rest}] — direct call
      final rest = parts.length > 3 ? parts.sublist(3).join('/') : '';
      originalPath = rest.isEmpty ? '/' : '/$rest';
    } else {
      continue;
    }

    if (currentRequest.method.toUpperCase() == 'OPTIONS' &&
        function.allowedOrigins != null) {
      return _buildOptionsCorsResponse(
        currentRequest,
        function.allowedOrigins!,
      );
    }

    if (!function.external && currentRequest.method.toUpperCase() != 'POST') {
      continue;
    }

    // Reconstruct the request with the original path so handlers see the same
    // path they would in production Cloud Run.
    final handlerRequest = _withOriginalPath(currentRequest, originalPath);

    final wrappedHandler = withInit(function.handler);
    final response = await wrappedHandler(handlerRequest);
    if (function.allowedOrigins != null) {
      return _applyCorsHeaders(
        handlerRequest,
        response,
        function.allowedOrigins!,
      );
    }
    return response;
  }

  // No matching function found.
  final notFoundName = xFirebaseFunction ?? (parts.isNotEmpty ? parts[0] : '');
  return Response.notFound(
    'Function not found: $notFoundName\n'
    'Available functions: ${functions.map((f) => f.name).join(", ")}',
  );
}

/// Tries to match a function by parsing CloudEvent headers or body.
///
/// Supports both:
/// - Binary content mode: CloudEvent metadata in ce-* headers, protobuf body
/// - Structured content mode: CloudEvent as JSON body
///
/// Returns a record of (Request, FirebaseFunctionDeclaration?) where the Request
/// is recreated with the body if we consumed the original stream.
/// The FirebaseFunctionDeclaration is null if this is not a CloudEvent request.
Future<(Request, FirebaseFunctionDeclaration?)> _tryMatchCloudEventFunction(
  Request request,
  List<FirebaseFunctionDeclaration> functions,
) async {
  try {
    String? bodyString; // Only set for structured mode
    final isBinaryMode =
        request.headers.containsKey('ce-type') &&
        request.headers.containsKey('ce-source');

    String source;
    String type;

    // Check for binary content mode (CloudEvent metadata in headers)
    if (isBinaryMode) {
      final ceType = request.headers['ce-type'];
      final ceSource = request.headers['ce-source'];

      if (ceType == null || ceSource == null) {
        return (request, null);
      }

      type = ceType;
      source = ceSource;
    } else {
      // Check content-type to see if this might be structured mode
      final contentType = request.headers['content-type'];
      final isJson = contentType?.contains('application/json') ?? false;
      final isCloudEvent =
          contentType?.contains('application/cloudevents') ?? false;
      if (!isJson && !isCloudEvent) {
        return (request, null);
      }

      // Structured content mode - try to parse JSON body
      bodyString = await request.readAsString();

      final Map<String, dynamic> body;
      try {
        body = jsonDecode(bodyString) as Map<String, dynamic>;
      } catch (e) {
        // Invalid JSON - not a CloudEvent request
        return (request.change(body: bodyString), null);
      }

      final bodyType = body['type'];
      final bodySource = body['source'];
      // Check if this is a valid CloudEvent - if not, return reconstructed request
      if (bodyType is! String || bodySource is! String) {
        // Return the reconstructed request since we consumed the body
        return (request.change(body: bodyString), null);
      }

      source = bodySource;
      type = bodyType;
    }

    // Now we have source and type from either headers or body
    // Handle Pub/Sub CloudEvents
    // Source format: //pubsub.googleapis.com/projects/{project}/topics/{topic}
    if (type == 'google.cloud.pubsub.topic.v1.messagePublished' &&
        source.contains('/topics/')) {
      final topicName = source.split('/topics/').last;

      // Sanitize topic name to match function naming convention
      // Topic "my-topic" becomes function "on-message-published-mytopic"
      final sanitizedTopic = topicName.replaceAll('-', '').toLowerCase();
      final expectedFunctionName = toCloudRunId(
        'onMessagePublished_$sanitizedTopic',
      );

      // Try to find a matching function
      for (final function in functions) {
        if (function.name == expectedFunctionName && !function.external) {
          // For structured mode, recreate request with body; for binary mode, use original
          final newRequest = bodyString != null
              ? request.change(body: bodyString)
              : request;
          return (newRequest, function);
        }
      }
    }

    // Handle Firestore CloudEvents
    // Source format: //firestore.googleapis.com/projects/{project}/databases/{database}/documents/{document}
    // Or use ce-document header in binary mode
    // Event types:
    // - google.cloud.firestore.document.v1.created
    // - google.cloud.firestore.document.v1.updated
    // - google.cloud.firestore.document.v1.deleted
    // - google.cloud.firestore.document.v1.written
    if (type.startsWith('google.cloud.firestore.document.v1.')) {
      // Extract document path from ce-document header (binary mode) or source (structured mode)
      String? documentPath;
      if (isBinaryMode && request.headers.containsKey('ce-document')) {
        documentPath = request.headers['ce-document'];
      } else if (source.contains('/documents/')) {
        documentPath = source.split('/documents/').last;
      }

      if (documentPath != null) {
        // Map CloudEvent type to method name
        final methodName = _mapCloudEventTypeToFirestoreMethod(type);
        if (methodName != null) {
          final methodPrefix = toCloudRunId(methodName);
          // Try to find a matching function by pattern matching
          for (final function in functions) {
            if (!function.external && function.name.startsWith(methodPrefix)) {
              // Check if this function has a document pattern to match against
              if (function.documentPattern != null) {
                if (_matchesDocumentPattern(
                  documentPath,
                  function.documentPattern!,
                )) {
                  // For structured mode, recreate request with body; for binary mode, use original
                  final newRequest = bodyString != null
                      ? request.change(body: bodyString)
                      : request;
                  return (newRequest, function);
                }
              }
            }
          }
        }
      }
    }

    // Handle Realtime Database CloudEvents
    // Event types:
    // - google.firebase.database.ref.v1.created
    // - google.firebase.database.ref.v1.updated
    // - google.firebase.database.ref.v1.deleted
    // - google.firebase.database.ref.v1.written
    // Binary mode headers: ce-ref (path), ce-instance (database instance)
    if (type.startsWith('google.firebase.database.ref.v1.')) {
      // Extract ref path from ce-ref header (binary mode)
      String? refPath;
      if (isBinaryMode && request.headers.containsKey('ce-ref')) {
        refPath = request.headers['ce-ref'];
      }

      if (refPath != null) {
        // Map CloudEvent type to method name
        final methodName = _mapCloudEventTypeToDatabaseMethod(type);
        if (methodName != null) {
          final methodPrefix = toCloudRunId(methodName);
          // Try to find a matching function by pattern matching
          for (final function in functions) {
            if (!function.external && function.name.startsWith(methodPrefix)) {
              // Check if this function has a ref pattern to match against
              if (function.refPattern != null) {
                if (_matchesRefPattern(refPath, function.refPattern!)) {
                  // For structured mode, recreate request with body; for binary mode, use original
                  final newRequest = bodyString != null
                      ? request.change(body: bodyString)
                      : request;
                  return (newRequest, function);
                }
              }
            }
          }
        }
      }
    }

    // Handle Storage CloudEvents
    // Source format: //storage.googleapis.com/projects/_/buckets/{bucket}
    // Event types:
    // - google.cloud.storage.object.v1.archived
    // - google.cloud.storage.object.v1.finalized
    // - google.cloud.storage.object.v1.deleted
    // - google.cloud.storage.object.v1.metadataUpdated
    if (type.startsWith('google.cloud.storage.object.v1.')) {
      // Extract bucket name from source URL
      // Source format: //storage.googleapis.com/projects/_/buckets/{bucket}/objects/{path}
      // or just: //storage.googleapis.com/projects/_/buckets/{bucket}
      String? bucketName;
      if (source.contains('/buckets/')) {
        final afterBuckets = source.split('/buckets/').last;
        // Bucket name is the first path segment (before any /objects/... suffix)
        bucketName = afterBuckets.split('/').first;
      }

      if (bucketName != null) {
        // Map CloudEvent type to method name
        final methodName = _mapCloudEventTypeToStorageMethod(type);
        if (methodName != null) {
          // Sanitize bucket name to match function naming convention
          final sanitizedBucket = bucketName.replaceAll(
            RegExp('[^a-zA-Z0-9]'),
            '',
          );
          final expectedFunctionName = toCloudRunId(
            '${methodName}_$sanitizedBucket',
          );

          // Try to find a matching function
          for (final function in functions) {
            if (function.name == expectedFunctionName && !function.external) {
              final newRequest = bodyString != null
                  ? request.change(body: bodyString)
                  : request;
              return (newRequest, function);
            }
          }
        }
      }
    }

    // TODO: Add support for other CloudEvent types (Auth, etc.)

    // No CloudEvent function matched - return reconstructed request if we read the body
    final finalRequest = bodyString != null
        ? request.change(body: bodyString)
        : request;
    return (finalRequest, null);
  } catch (e, stackTrace) {
    // CloudEvent parsing failed - not a CloudEvent request
    logger.warn(
      'CloudEvent parsing failed: $e\n${Trace.from(stackTrace).terse}',
    );
    return (request, null);
  }
}

/// Creates a copy of [request] with [originalPath] set on its `requestedUri`
/// so that handlers see the original client path rather than the routing prefix
/// added by the emulator. Returns [request] unchanged if the path already matches.
Request _withOriginalPath(Request request, String originalPath) {
  if (request.requestedUri.path == originalPath) return request;
  return Request(
    request.method,
    request.requestedUri.replace(path: originalPath),
    headers: request.headers,
    body: request.read(),
    context: request.context,
  );
}

/// Handles the /__/quitquitquit graceful shutdown endpoint.
///
/// This endpoint is used by Cloud Run to signal graceful shutdown.
/// Matches Node.js implementation in firebase-functions.
Response _handleQuitQuitQuit(Request request) {
  // Accept both GET and POST like Node.js does
  if (request.method != 'GET' && request.method != 'POST') {
    return Response(405, headers: {'Allow': 'GET, POST'});
  }

  // In Node.js, this closes the HTTP server
  // In Dart, we'll just acknowledge the request
  // Actual shutdown would need to be handled by the server instance
  return Response.ok('OK');
}

/// Handles the /__/functions.yaml manifest endpoint.
///
/// Returns the functions manifest when FUNCTIONS_CONTROL_API is enabled.
/// This is used by firebase-tools for function discovery.
FutureOr<Response> _handleFunctionsManifest(
  Request request,
  Firebase firebase,
) {
  if (request.method != 'GET') {
    return Response(405, headers: {'Allow': 'GET'});
  }

  // Read the generated manifest file
  final manifestPath = 'functions.yaml';
  final manifestFile = File(manifestPath);

  if (!manifestFile.existsSync()) {
    return Response.notFound(
      'functions.yaml not found at $manifestPath. '
      'Run "dart run build_runner build" to generate it.',
    );
  }

  final manifestContent = manifestFile.readAsStringSync();
  return Response.ok(
    manifestContent,
    headers: {'Content-Type': 'text/yaml; charset=utf-8'},
  );
}

/// Maps Firestore CloudEvent type to method name.
String? _mapCloudEventTypeToFirestoreMethod(String eventType) =>
    switch (eventType) {
      'google.cloud.firestore.document.v1.created' => 'onDocumentCreated',
      'google.cloud.firestore.document.v1.updated' => 'onDocumentUpdated',
      'google.cloud.firestore.document.v1.deleted' => 'onDocumentDeleted',
      'google.cloud.firestore.document.v1.written' => 'onDocumentWritten',
      _ => null,
    };

/// Matches a document path against a pattern with wildcards.
///
/// Examples:
/// - 'users/123' matches 'users/{userId}'
/// - 'users/123/posts/456' matches 'users/{userId}/posts/{postId}'
/// - 'users/123' does NOT match 'posts/{postId}'
bool _matchesDocumentPattern(String documentPath, String pattern) {
  // Split both paths by '/'
  final docParts = documentPath.split('/');
  final patternParts = pattern.split('/');

  // Paths must have same number of segments
  if (docParts.length != patternParts.length) {
    return false;
  }

  // Check each segment
  for (var i = 0; i < docParts.length; i++) {
    final docPart = docParts[i];
    final patternPart = patternParts[i];

    // If pattern part is a wildcard (contains {})
    if (patternPart.startsWith('{') && patternPart.endsWith('}')) {
      // Wildcard matches any value
      continue;
    }

    // Not a wildcard - must match exactly
    if (docPart != patternPart) {
      return false;
    }
  }

  return true;
}

/// Maps Database CloudEvent type to method name.
String? _mapCloudEventTypeToDatabaseMethod(String eventType) =>
    switch (eventType) {
      'google.firebase.database.ref.v1.created' => 'onValueCreated',
      'google.firebase.database.ref.v1.updated' => 'onValueUpdated',
      'google.firebase.database.ref.v1.deleted' => 'onValueDeleted',
      'google.firebase.database.ref.v1.written' => 'onValueWritten',
      _ => null,
    };

/// Maps Storage CloudEvent type to method name.
String? _mapCloudEventTypeToStorageMethod(String eventType) =>
    switch (eventType) {
      'google.cloud.storage.object.v1.archived' => 'onObjectArchived',
      'google.cloud.storage.object.v1.finalized' => 'onObjectFinalized',
      'google.cloud.storage.object.v1.deleted' => 'onObjectDeleted',
      'google.cloud.storage.object.v1.metadataUpdated' =>
        'onObjectMetadataUpdated',
      _ => null,
    };

/// Matches a database ref path against a pattern with wildcards.
///
/// Examples:
/// - 'messages/abc123' matches 'messages/{messageId}'
/// - 'users/123/status' matches 'users/{userId}/status'
/// - 'messages/abc123' does NOT match 'users/{userId}'
bool _matchesRefPattern(String refPath, String pattern) {
  // Split both paths by '/'
  final refParts = refPath.split('/');
  final patternParts = pattern.split('/');

  // Paths must have same number of segments
  if (refParts.length != patternParts.length) {
    return false;
  }

  // Check each segment
  for (var i = 0; i < refParts.length; i++) {
    final refPart = refParts[i];
    final patternPart = patternParts[i];

    // If pattern part is a wildcard (contains {})
    if (patternPart.startsWith('{') && patternPart.endsWith('}')) {
      // Wildcard matches any value
      continue;
    }

    // Not a wildcard - must match exactly
    if (refPart != patternPart) {
      return false;
    }
  }

  return true;
}

final _traceIdRegExp = RegExp(r'^[a-f0-9]{32}$', caseSensitive: false);

/// Extracts the 32-character hexadecimal trace ID from an [x-cloud-trace-context] header.
///
/// Expected format: `TRACE_ID/SPAN_ID;o=TRACE_TRUE`
@visibleForTesting
String? extractTraceId(String? header) {
  if (header == null || header.isEmpty) return null;
  final parts = header.split('/');
  if (parts.isNotEmpty) {
    final traceId = parts[0];
    if (_traceIdRegExp.hasMatch(traceId)) {
      return traceId;
    }
  }
  return null;
}
