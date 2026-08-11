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

import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart';

import '../../logger.dart' as logger;
import '../common/options.dart';
import 'options.dart';

/// The default methods advertised in a preflight response.
///
/// Matches the default of the `cors` middleware used by the Node.js SDK.
const defaultCorsMethods = <String>[
  'GET',
  'HEAD',
  'PUT',
  'PATCH',
  'POST',
  'DELETE',
];

/// The methods advertised by callable functions, which only accept `POST`.
const callableCorsMethods = <String>['POST'];

/// A [Cors] value that allows any origin.
///
/// The request's `Origin` header is reflected back rather than a literal `*`,
/// matching `cors: true` in the Node.js SDK.
const corsAllowAnyOrigin = Cors(_anyOrigin);

/// A [Cors] value that disables CORS, emitting no CORS response headers.
///
/// Equivalent to `cors: false` in the Node.js SDK.
const corsDisabled = Cors(<String>[]);

const _anyOrigin = ['*'];

/// Unresolved CORS configuration attached to an HTTPS function declaration.
///
/// The origin list is deliberately *not* resolved at registration time. The
/// Node.js SDK resolves it per request so that a parameter or expression which
/// is not yet available at cold start does not permanently poison the function,
/// and so that a failure degrades to "CORS off" instead of crashing startup.
@internal
final class CorsConfig {
  const CorsConfig({
    this.option,
    this.methods = defaultCorsMethods,
    this.enabledByDefault = false,
  });

  /// The user-supplied option, if any.
  final Cors? option;

  /// Methods advertised in `Access-Control-Allow-Methods` on preflight.
  final List<String> methods;

  /// Whether CORS is on when the user supplied no [option].
  ///
  /// True for callable functions, false for `onRequest`.
  final bool enabledByDefault;

  /// Resolves the effective allow-list for a single request.
  ///
  /// Returns `null` when CORS is disabled and no headers should be emitted.
  /// Returns `['*']` to mean "any origin" (reflect the request's `Origin`).
  List<String>? resolveOrigins({required bool debugCorsEnabled}) {
    final explicit = _resolveOption();

    // An empty list is how `cors: false` is expressed in Dart. Respect it even
    // when the emulator's enableCors debug feature is on, matching Node.js.
    final explicitlyDisabled = explicit != null && explicit.isEmpty;

    if (debugCorsEnabled) {
      return explicitlyDisabled ? null : _anyOrigin;
    }
    if (explicit != null) {
      return explicitlyDisabled ? null : explicit;
    }
    return enabledByDefault ? _anyOrigin : null;
  }

  List<String>? _resolveOption() {
    final option = this.option;
    if (option == null) return null;
    try {
      final value = option.runtimeValue();
      // An empty literal is the documented way to turn CORS off, so it is not
      // worth warning about. An empty *resolved* value is more likely a
      // misconfigured param the user wants to hear about.
      if (value.isEmpty && option is! OptionLiteral<List<String>>) {
        logger.warning(
          'CORS option resolved to an empty list. Disabling CORS.',
        );
      }
      return value;
    } catch (e) {
      logger.warning('Failed to resolve CORS option: $e. Disabling CORS.');
      return const <String>[];
    }
  }
}

/// Builds the CORS response headers for [request].
///
/// [allowedOrigins] is the output of [CorsConfig.resolveOrigins]; `['*']` means
/// reflect any origin. Pass [isPreflight] for `OPTIONS` requests, which are the
/// only responses that carry `Access-Control-Allow-Methods` and
/// `Access-Control-Allow-Headers`.
///
/// Mirrors the header set produced by the `cors` middleware in the Node.js SDK.
@visibleForTesting
Map<String, String> corsHeadersFor(
  Request request,
  List<String>? allowedOrigins, {
  bool isPreflight = false,
  List<String> methods = defaultCorsMethods,
}) {
  if (allowedOrigins == null || allowedOrigins.isEmpty) return const {};

  final headers = <String, String>{};
  final varyOn = <String>['Origin'];

  final requestOrigin = request.headers['origin'];
  final allowAny = allowedOrigins.contains('*');

  // `Access-Control-Allow-Origin` is omitted entirely when the origin is not
  // allowed (or absent). The browser then blocks the response, which is the
  // same outcome the Node.js SDK produces.
  if (requestOrigin != null &&
      (allowAny || allowedOrigins.contains(requestOrigin))) {
    // Reflect the origin rather than emitting a literal `*`: `*` is rejected by
    // the browser for credentialed requests and cannot be cached per-origin.
    headers['Access-Control-Allow-Origin'] = requestOrigin;
  }

  if (isPreflight) {
    headers['Access-Control-Allow-Methods'] = methods.join(',');

    // Reflect the requested headers verbatim. A literal `*` does NOT authorise
    // `Authorization` (the Fetch spec excludes it from the wildcard), which
    // every authenticated callable request sends.
    final requestedHeaders = request.headers['access-control-request-headers'];
    if (requestedHeaders != null && requestedHeaders.isNotEmpty) {
      headers['Access-Control-Allow-Headers'] = requestedHeaders;
      varyOn.add('Access-Control-Request-Headers');
    }
  }

  // The response body/headers depend on the request's Origin, so it must be
  // declared or intermediate caches will serve one origin's response to another.
  headers['Vary'] = varyOn.join(', ');

  return headers;
}

/// Builds the response to a CORS preflight (`OPTIONS`) request.
@internal
Response buildPreflightResponse(
  Request request,
  List<String>? allowedOrigins, {
  List<String> methods = defaultCorsMethods,
}) => Response(
  204,
  headers: {
    ...corsHeadersFor(
      request,
      allowedOrigins,
      isPreflight: true,
      methods: methods,
    ),
    'Content-Length': '0',
  },
);

/// Adds CORS headers to an already-built [response].
@internal
Response applyCorsHeaders(
  Request request,
  Response response,
  List<String>? allowedOrigins,
) {
  final headers = corsHeadersFor(request, allowedOrigins);
  if (headers.isEmpty) return response;
  return response.change(headers: _withMergedVary(response.headers, headers));
}

/// Merges the CORS `Vary` value into any `Vary` the response already carries.
///
/// Overwriting would silently drop a value the handler depends on — most often
/// `Accept-Encoding`, which affects how caches store the body. The `cors`
/// middleware in the Node.js SDK appends for the same reason.
Map<String, String> _withMergedVary(
  Map<String, String> responseHeaders,
  Map<String, String> corsHeaders,
) {
  final existing = responseHeaders['vary'];
  final added = corsHeaders['Vary'];
  if (existing == null || existing.isEmpty || added == null) return corsHeaders;

  // `Vary: *` already means "varies on everything"; narrowing it would be a lie.
  if (existing.split(',').any((value) => value.trim() == '*')) {
    return {...corsHeaders, 'Vary': '*'};
  }

  final seen = <String>{};
  final merged = <String>[];
  for (final value in [...existing.split(','), ...added.split(',')]) {
    final trimmed = value.trim();
    // Field names are case-insensitive, so dedupe on the lowered form but keep
    // the casing the response already used.
    if (trimmed.isNotEmpty && seen.add(trimmed.toLowerCase())) {
      merged.add(trimmed);
    }
  }
  return {...corsHeaders, 'Vary': merged.join(', ')};
}
