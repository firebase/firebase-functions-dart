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

import 'package:firebase_functions/src/common/expression.dart';
import 'package:firebase_functions/src/https/cors.dart';
import 'package:firebase_functions/src/https/options.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Request _request({
  String method = 'GET',
  String? origin,
  String? requestHeaders,
}) => Request(
  method,
  Uri.parse('http://localhost/test'),
  headers: {
    'origin': ?origin,
    'access-control-request-headers': ?requestHeaders,
  },
);

void main() {
  group('corsHeadersFor', () {
    test('reflects the request origin when any origin is allowed', () {
      final headers = corsHeadersFor(
        _request(origin: 'https://example.com'),
        ['*'],
      );

      // Reflecting rather than emitting a literal `*` matches `cors: true` in
      // the Node.js SDK, and is required for credentialed requests.
      expect(headers['Access-Control-Allow-Origin'], 'https://example.com');
      expect(headers['Vary'], 'Origin');
    });

    test('omits allow-origin when the request has no Origin header', () {
      final headers = corsHeadersFor(_request(), ['*']);

      expect(headers.containsKey('Access-Control-Allow-Origin'), isFalse);
      expect(headers['Vary'], 'Origin');
    });

    test('reflects an origin present in the allow-list', () {
      final headers = corsHeadersFor(_request(origin: 'https://example.com'), [
        'https://other.com',
        'https://example.com',
      ]);

      expect(headers['Access-Control-Allow-Origin'], 'https://example.com');
    });

    test('omits allow-origin for an origin not in the allow-list', () {
      final headers = corsHeadersFor(_request(origin: 'https://evil.com'), [
        'https://example.com',
      ]);

      expect(headers.containsKey('Access-Control-Allow-Origin'), isFalse);
      // Vary is still required: the response varies on Origin even when the
      // origin is rejected, or a cache will serve this to an allowed origin.
      expect(headers['Vary'], 'Origin');
    });

    test('emits nothing when CORS is disabled', () {
      expect(corsHeadersFor(_request(origin: 'https://a.com'), null), isEmpty);
      expect(
        corsHeadersFor(_request(origin: 'https://a.com'), const []),
        isEmpty,
      );
    });

    test('does not advertise methods or headers on non-preflight', () {
      final headers = corsHeadersFor(_request(origin: 'https://a.com'), ['*']);

      expect(headers.containsKey('Access-Control-Allow-Methods'), isFalse);
      expect(headers.containsKey('Access-Control-Allow-Headers'), isFalse);
    });

    group('preflight', () {
      test('advertises the configured methods', () {
        final headers = corsHeadersFor(
          _request(method: 'OPTIONS', origin: 'https://a.com'),
          ['*'],
          isPreflight: true,
          methods: callableCorsMethods,
        );

        expect(headers['Access-Control-Allow-Methods'], 'POST');
      });

      test('advertises default methods when unspecified', () {
        final headers = corsHeadersFor(
          _request(method: 'OPTIONS', origin: 'https://a.com'),
          ['*'],
          isPreflight: true,
        );

        expect(
          headers['Access-Control-Allow-Methods'],
          'GET,HEAD,PUT,PATCH,POST,DELETE',
        );
      });

      test('reflects requested headers verbatim, including Authorization', () {
        // A literal `*` in Access-Control-Allow-Headers does NOT authorise
        // `Authorization` per the Fetch spec, so it must be echoed explicitly.
        // Every authenticated callable request sends it.
        final headers = corsHeadersFor(
          _request(
            method: 'OPTIONS',
            origin: 'https://a.com',
            requestHeaders: 'authorization,content-type',
          ),
          ['*'],
          isPreflight: true,
        );

        expect(
          headers['Access-Control-Allow-Headers'],
          'authorization,content-type',
        );
        expect(headers['Vary'], 'Origin, Access-Control-Request-Headers');
      });

      test('omits allow-headers when none were requested', () {
        final headers = corsHeadersFor(
          _request(method: 'OPTIONS', origin: 'https://a.com'),
          ['*'],
          isPreflight: true,
        );

        expect(headers.containsKey('Access-Control-Allow-Headers'), isFalse);
        expect(headers['Vary'], 'Origin');
      });
    });
  });

  group('buildPreflightResponse', () {
    test('responds 204 with an empty body', () async {
      final response = buildPreflightResponse(
        _request(method: 'OPTIONS', origin: 'https://a.com'),
        ['*'],
      );

      expect(response.statusCode, 204);
      expect(await response.readAsString(), isEmpty);
      expect(response.headers['content-length'], '0');
      expect(response.headers['access-control-allow-origin'], 'https://a.com');
    });
  });

  group('applyCorsHeaders', () {
    test('leaves the response untouched when CORS is disabled', () {
      final original = Response.ok('body');
      final result = applyCorsHeaders(
        _request(origin: 'https://a.com'),
        original,
        null,
      );

      expect(result, same(original));
    });

    test('preserves existing response headers', () {
      final result = applyCorsHeaders(
        _request(origin: 'https://a.com'),
        Response.ok('{}', headers: {'Content-Type': 'application/json'}),
        ['*'],
      );

      expect(result.headers['content-type'], 'application/json');
      expect(result.headers['access-control-allow-origin'], 'https://a.com');
    });
  });

  group('CorsConfig.resolveOrigins', () {
    test('onRequest default is off', () {
      const config = CorsConfig();
      expect(config.resolveOrigins(debugCorsEnabled: false), isNull);
    });

    test('callable default is any origin', () {
      const config = CorsConfig(enabledByDefault: true);
      expect(config.resolveOrigins(debugCorsEnabled: false), ['*']);
    });

    test('uses an explicit allow-list', () {
      const config = CorsConfig(option: Cors(['https://example.com']));
      expect(config.resolveOrigins(debugCorsEnabled: false), [
        'https://example.com',
      ]);
    });

    test('an empty list disables CORS', () {
      const config = CorsConfig(
        option: corsDisabled,
        enabledByDefault: true,
      );
      expect(config.resolveOrigins(debugCorsEnabled: false), isNull);
    });

    test('emulator debug feature enables CORS for an unconfigured function', () {
      const config = CorsConfig();
      expect(config.resolveOrigins(debugCorsEnabled: true), ['*']);
    });

    test('emulator debug feature widens an explicit allow-list', () {
      const config = CorsConfig(option: Cors(['https://example.com']));
      expect(config.resolveOrigins(debugCorsEnabled: true), ['*']);
    });

    test('emulator debug feature respects an explicit opt-out', () {
      // Matches the Node.js SDK: `cors: false` stays off even under the
      // emulator, so local behaviour reproduces production.
      const config = CorsConfig(option: corsDisabled);
      expect(config.resolveOrigins(debugCorsEnabled: true), isNull);
    });

    test('disables CORS when the option throws instead of crashing', () {
      const config = CorsConfig(
        option: Cors.expression(_ThrowingExpression()),
        enabledByDefault: true,
      );

      expect(config.resolveOrigins(debugCorsEnabled: false), isNull);
    });

    test('resolves an expression to its runtime value', () {
      const config = CorsConfig(
        option: Cors.expression(
          LiteralExpression(['https://example.com']),
        ),
      );

      expect(config.resolveOrigins(debugCorsEnabled: false), [
        'https://example.com',
      ]);
    });
  });
}

final class _ThrowingExpression extends Expression<List<String>> {
  const _ThrowingExpression();

  @override
  List<String> runtimeValue() => throw StateError('unavailable');

  @override
  String toCEL() => 'broken';
}
