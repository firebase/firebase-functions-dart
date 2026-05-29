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
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

import '../../logger.dart' as logger;
import '../logger/logger.dart';
import 'error.dart';

/// JSON decoder function type.
typedef JsonDecoder<T extends Object?> = T Function(Map<String, dynamic>);

/// Result of a callable function.
///
/// Wraps the return value from a callable function handler.
///
/// Example:
/// ```dart
/// firebase.https.onCall(
///   name: 'greet',
///   (request, response) async {
///     return CallableResult('Hello!');
///   },
/// );
/// ```
class CallableResult<T extends Object> {
  CallableResult(this.data);
  final T data;

  /// Converts this result to a Shelf Response.
  Response toResponse() => Response.ok(
    jsonEncode({'result': data}),
    headers: {HttpHeaders.contentTypeHeader: 'application/json'},
  );
}

/// A callable result that returns JSON data.
///
/// This is a convenience class for returning Map data as a JSON response.
///
/// Example:
/// ```dart
/// firebase.https.onCall(
///   name: 'greet',
///   (request, response) async {
///     return JsonResult({'status': 'ok', 'message': 'Hello!'});
///   },
/// );
/// ```
class JsonResult extends CallableResult<Map<String, dynamic>> {
  JsonResult(super.data);
}

/// Firebase Auth context data for a callable request.
///
/// Contains information about the authenticated user.
class AuthData {
  const AuthData({required this.uid, this.token, this.rawToken});

  /// The user's unique ID.
  final String uid;

  /// The decoded ID token claims.
  final Map<String, dynamic>? token;

  /// The raw JWT token string.
  ///
  /// This can be used to pass the token to other services or for debugging.
  final String? rawToken;
}

/// Firebase App Check context data for a callable request.
///
/// Contains information about the verified App Check token.
class AppCheckData {
  const AppCheckData({required this.appId, this.token, this.alreadyConsumed});

  /// The App ID from the App Check token.
  final String appId;

  /// The raw App Check token.
  final String? token;

  /// Whether this token was already consumed (replay protection).
  final bool? alreadyConsumed;
}

/// Request context for a callable function.
///
/// Provides access to request data, authentication context, and headers.
///
/// Example:
/// ```dart
/// firebase.https.onCall(
///   name: 'greet',
///   (request, response) async {
///     final data = request.data;
///     print('Can stream?: ${request.acceptsStreaming}');
///     if (request.auth != null) {
///       print('User ID: ${request.auth!.uid}');
///     }
///     return CallableResult('Hello!');
///   },
/// );
/// ```
class CallableRequest<T extends Object?> {
  CallableRequest(
    this._delegate,
    this._body,
    this._jsonDecoder, {
    this.auth,
    this.app,
  });
  final Request _delegate;
  final Object? _body;
  final JsonDecoder<T>? _jsonDecoder;

  /// The request data (from the 'data' field in the request body).
  T get data {
    final decoded = decode(_body);

    if (_jsonDecoder == null) {
      // Use dynamic cast for flexibility
      return decoded as T;
    }

    // If jsonDecoder is provided, decoded must be a Map
    if (decoded is! Map<String, dynamic>) {
      throw StateError(
        'Expected Map<String, dynamic> for jsonDecoder, but got ${decoded.runtimeType}',
      );
    }

    return _jsonDecoder(decoded);
  }

  /// Whether the client accepts streaming (SSE) responses.
  bool get acceptsStreaming =>
      _delegate.headers['accept'] == 'text/event-stream';

  /// Firebase App Check context.
  ///
  /// Contains information about the verified App Check token.
  /// Returns `null` if App Check was not provided or validation failed.
  final AppCheckData? app;

  /// Firebase Authentication context.
  ///
  /// Contains information about the authenticated user.
  /// Returns `null` if the request is not authenticated.
  final AuthData? auth;

  /// Firebase Instance ID token.
  String? get instanceIdToken =>
      _delegate.headers['Firebase-Instance-ID-Token'];

  /// The raw Shelf request.
  Request get rawRequest => _delegate;
}

/// Response helper for callable functions.
///
/// Provides streaming support via Server-Sent Events (SSE).
///
/// Example:
/// ```dart
/// firebase.https.onCall(
///   name: 'streamData',
///   (request, response) async {
///     final stream = Stream.periodic(
///       Duration(seconds: 1),
///       (x) => CallableResult(x),
///     ).take(10);
///
///     if (request.acceptsStreaming) {
///       response.stream(stream);
///     }
///
///     return CallableResult('done');
///   },
/// );
/// ```
class CallableResponse<T extends Object> {
  CallableResponse({required this.acceptsStreaming, this.heartbeatSeconds});

  static final _dataPrefix = utf8.encode('data: ');
  static final _newlineSuffix = utf8.encode('\n\n');
  static final _pingBytes = utf8.encode(': ping\n\n');
  final bool acceptsStreaming;
  final int? heartbeatSeconds;

  StreamController<List<int>>? _streamController;
  Response? _streamingResponse;
  Timer? _heartbeatTimer;
  StreamSubscription<CallableResult<T>>? _streamSubscription;
  bool _aborted = false;
  bool _isUsingResponseStream = false;

  /// Whether [stream] was called to set up background streaming.
  bool get isUsingResponseStream => _isUsingResponseStream;

  /// Initializes SSE streaming.
  void initializeStreaming() {
    _streamController = StreamController<List<int>>(
      onCancel: () {
        abort();
      },
    );
    _streamingResponse = Response.ok(
      _streamController!.stream,
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
      },
    );

    // Schedule heartbeat if configured
    if (heartbeatSeconds != null && heartbeatSeconds! > 0) {
      _scheduleHeartbeat();
    }
  }

  /// Streams data to the client via Server-Sent Events.
  ///
  /// When provided, streams any emitted events from the stream to the client.
  /// Each item from the stream is wrapped in an SSE data event.
  ///
  /// Example:
  /// ```dart
  /// final stream = Stream.periodic(
  ///   Duration(seconds: 1),
  ///   (x) => CallableResult({'count': x}),
  /// ).take(10);
  ///
  /// if (request.acceptsStreaming) {
  ///   response.stream(stream);
  /// }
  /// ```
  void stream(Stream<CallableResult<T>> dataStream) {
    if (!acceptsStreaming) {
      return;
    }

    _isUsingResponseStream = true;

    _streamSubscription = dataStream.listen(
      (result) {
        unawaited(sendChunk(result.data));
      },
      onError: (Object error) {
        logger.error(
          'Error in data stream',
          {'error': error.toString()},
        );
        if (error is HttpsError) {
          writeSSE(error.toErrorResponse());
        } else {
          writeSSE(InternalError().toErrorResponse());
        }
        unawaited(closeStream());
      },
      onDone: () async {
        await closeStream();
      },
      cancelOnError: true,
    );
  }

  /// Sends a chunk of data to the client via SSE.
  ///
  /// Returns true if the chunk was sent successfully, false if streaming
  /// is not active or the connection was closed.
  Future<bool> sendChunk(T chunk) async {
    if (!acceptsStreaming) {
      return false;
    }

    if (_aborted || _streamController == null || _streamController!.isClosed) {
      return false;
    }

    try {
      _streamController!.add(_encodeSSE({'message': chunk}));

      // Reset heartbeat timer after successful write
      if (heartbeatSeconds != null && heartbeatSeconds! > 0) {
        _scheduleHeartbeat();
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Writes an SSE event to the stream.
  void writeSSE(Map<String, dynamic> data) {
    if (_streamController == null || _streamController!.isClosed) {
      return;
    }
    _streamController!.add(_encodeSSE(data));
  }

  /// Closes the streaming response.
  Future<void> closeStream() async {
    await _streamSubscription?.cancel();
    _streamSubscription = null;

    clearHeartbeat();

    if (_streamController != null && !_streamController!.isClosed) {
      await _streamController!.close();
    }
  }

  /// Clears the heartbeat timer.
  void clearHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Gets the streaming response (for internal use).
  Response? get streamingResponse => _streamingResponse;

  /// Whether the stream has been aborted.
  bool get aborted => _aborted;

  /// Marks the stream as aborted.
  void abort() {
    _aborted = true;
    unawaited(_streamSubscription?.cancel());
    _streamSubscription = null;
    clearHeartbeat();
  }

  /// Schedules the next heartbeat ping.
  void _scheduleHeartbeat() {
    clearHeartbeat();

    if (heartbeatSeconds == null || heartbeatSeconds! <= 0) {
      return;
    }

    _heartbeatTimer = Timer(Duration(seconds: heartbeatSeconds!), () {
      if (!_aborted &&
          _streamController != null &&
          !_streamController!.isClosed) {
        _streamController!.add(_pingBytes);
        _scheduleHeartbeat();
      }
    });
  }

  /// Encodes data as SSE format.
  List<int> _encodeSSE(Map<String, dynamic> data) {
    final jsonBytes = json.fuse(utf8).encode(data);
    return (BytesBuilder(copy: false)
          ..add(_dataPrefix)
          ..add(jsonBytes)
          ..add(_newlineSuffix))
        .takeBytes();
  }
}

/// Decodes request data, handling special types (like Int64).
///
/// Matches the decode behavior from the Node.js SDK.
Object? decode(Object? body) {
  if (body == null) {
    return body;
  }

  if (body is List) {
    return body.map(decode).toList();
  }

  if (body is Map) {
    // Handle special @type encoding for Int64/UInt64
    if (body.containsKey('@type')) {
      final type = body['@type'];
      if (type == 'type.googleapis.com/google.protobuf.Int64Value' ||
          type == 'type.googleapis.com/google.protobuf.UInt64Value') {
        final value = double.tryParse(body['value'].toString());
        if (value == null) {
          throw FormatException('Invalid Int64/UInt64 value: ${body['value']}');
        }
        return value;
      }
      throw FormatException('Unsupported @type: $type');
    }

    // Return a properly typed Map<String, dynamic>
    final result = <String, dynamic>{};
    for (final entry in body.entries) {
      result[entry.key.toString()] = decode(entry.value);
    }
    return result;
  }

  return body;
}

/// Encodes response data for transmission.
///
/// Matches the encode behavior from the Node.js SDK.
Object? encode(Object? data) {
  if (data == null) {
    return null;
  }

  // Numbers
  if (data is num) {
    if (data.isFinite) {
      return data;
    }
    throw ArgumentError('Cannot encode non-finite number: $data');
  }

  // Booleans and strings
  if (data is bool || data is String) {
    return data;
  }

  // DateTime
  if (data is DateTime) {
    return data.toIso8601String();
  }

  // Lists
  if (data is List) {
    return data.map(encode).toList();
  }

  // Maps
  if (data is Map) {
    final obj = <String, dynamic>{};
    data.forEach((k, v) {
      obj[k.toString()] = encode(v);
    });
    return obj;
  }

  throw ArgumentError('Data cannot be encoded in JSON: $data');
}

/// Extension methods for Request validation.
extension RequestValidation on Request {
  /// Parses JSON from the request body.
  Future<Object?> get json async {
    final body = await change().readAsString();
    return body.isEmpty ? null : jsonDecode(body);
  }

  /// Validates that this is a valid callable request.
  ///
  /// Checks:
  /// - Method is POST
  /// - Content-Type is application/json
  /// - Body contains only 'data' field
  Future<bool> isValidRequest([Map<String, dynamic>? body]) async {
    // Get body (use provided or read from request)
    final requestBody = body ?? await json;

    if (requestBody == null) {
      return false;
    }

    // Must be POST
    if (method.toUpperCase() != 'POST') {
      return false;
    }

    // Must be application/json
    var contentType = headers[HttpHeaders.contentTypeHeader] ?? '';
    final semiColonIndex = contentType.indexOf(';');
    if (semiColonIndex >= 0) {
      contentType = contentType.substring(0, semiColonIndex).trim();
    }

    if (contentType != 'application/json') {
      return false;
    }

    // Body must be a Map with only 'data' field
    if (requestBody is! Map<String, dynamic>) {
      return false;
    }

    final extraKeys = requestBody.keys
        .where((field) => field != 'data')
        .toList();
    if (extraKeys.isNotEmpty) {
      return false;
    }

    return true;
  }
}
