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
    test('wildcard emits a literal star and no Vary', () {
      // Mirrors `cors: '*'`: the response does not depend on the origin.
      final headers = corsHeadersFor(
        _request(origin: 'https://a.com'),
        const CorsWildcard(),
      );

      expect(headers['Access-Control-Allow-Origin'], '*');
      expect(headers.containsKey('Vary'), isFalse);
    });

    test('reflect-any echoes the request origin with Vary', () {
      final headers = corsHeadersFor(
        _request(origin: 'https://a.com'),
        const CorsReflectAny(),
      );

      expect(headers['Access-Control-Allow-Origin'], 'https://a.com');
      expect(headers['Vary'], 'Origin');
    });

    test('reflect-any omits the header when there is no Origin', () {
      final headers = corsHeadersFor(_request(), const CorsReflectAny());

      expect(headers.containsKey('Access-Control-Allow-Origin'), isFalse);
      expect(headers['Vary'], 'Origin');
    });

    test('fixed origin is emitted even when the request differs', () {
      // Node.js collapses a one-element allow-list to a bare string, which the
      // cors middleware sets unconditionally; the browser rejects a mismatch.
      final headers = corsHeadersFor(
        _request(origin: 'https://evil.com'),
        const CorsFixedOrigin('https://example.com'),
      );

      expect(headers['Access-Control-Allow-Origin'], 'https://example.com');
      expect(headers['Vary'], 'Origin');
    });

    test('match list reflects an allowed origin', () {
      final headers = corsHeadersFor(
        _request(origin: 'https://b.com'),
        const CorsMatchList(['https://a.com', 'https://b.com']),
      );

      expect(headers['Access-Control-Allow-Origin'], 'https://b.com');
    });

    test('match list omits the header for a disallowed origin', () {
      final headers = corsHeadersFor(
        _request(origin: 'https://evil.com'),
        const CorsMatchList(['https://a.com', 'https://b.com']),
      );

      expect(headers.containsKey('Access-Control-Allow-Origin'), isFalse);
      // Vary is still required, or a cache may serve this to an allowed origin.
      expect(headers['Vary'], 'Origin');
    });

    test('match list supports regex patterns', () {
      const decision = CorsMatchList([
        CorsPattern(r'^https://.*\.example\.com$'),
      ]);

      expect(
        corsHeadersFor(
          _request(origin: 'https://app.example.com'),
          decision,
        )['Access-Control-Allow-Origin'],
        'https://app.example.com',
      );
      expect(
        corsHeadersFor(
          _request(origin: 'https://example.com.evil.com'),
          decision,
        ).containsKey('Access-Control-Allow-Origin'),
        isFalse,
      );
    });

    test('an invalid regex is ignored rather than thrown', () {
      final headers = corsHeadersFor(
        _request(origin: 'https://a.com'),
        const CorsMatchList([CorsPattern('([unclosed')]),
      );

      expect(headers.containsKey('Access-Control-Allow-Origin'), isFalse);
    });

    test('emits nothing when disabled', () {
      expect(
        corsHeadersFor(_request(origin: 'https://a.com'), const CorsOff()),
        isEmpty,
      );
    });

    test('does not advertise methods or headers on non-preflight', () {
      final headers = corsHeadersFor(
        _request(origin: 'https://a.com'),
        const CorsReflectAny(),
      );

      expect(headers.containsKey('Access-Control-Allow-Methods'), isFalse);
      expect(headers.containsKey('Access-Control-Allow-Headers'), isFalse);
    });

    group('preflight', () {
      test('advertises the configured methods', () {
        final headers = corsHeadersFor(
          _request(method: 'OPTIONS', origin: 'https://a.com'),
          const CorsReflectAny(),
          isPreflight: true,
          methods: callableCorsMethods,
        );

        expect(headers['Access-Control-Allow-Methods'], 'POST');
      });

      test('advertises default methods when unspecified', () {
        final headers = corsHeadersFor(
          _request(method: 'OPTIONS', origin: 'https://a.com'),
          const CorsReflectAny(),
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
          const CorsReflectAny(),
          isPreflight: true,
        );

        expect(
          headers['Access-Control-Allow-Headers'],
          'authorization,content-type',
        );
        expect(headers['Vary'], 'Origin, Access-Control-Request-Headers');
      });

      test('varies on request-headers even when none were sent', () {
        // The cors middleware pushes this Vary unconditionally on preflight.
        final headers = corsHeadersFor(
          _request(method: 'OPTIONS', origin: 'https://a.com'),
          const CorsReflectAny(),
          isPreflight: true,
        );

        expect(headers.containsKey('Access-Control-Allow-Headers'), isFalse);
        expect(headers['Vary'], 'Origin, Access-Control-Request-Headers');
      });

      test('a wildcard preflight still varies on request-headers only', () {
        final headers = corsHeadersFor(
          _request(method: 'OPTIONS', origin: 'https://a.com'),
          const CorsWildcard(),
          isPreflight: true,
        );

        expect(headers['Access-Control-Allow-Origin'], '*');
        expect(headers['Vary'], 'Access-Control-Request-Headers');
      });
    });
  });

  group('applyCorsHeaders', () {
    test('leaves the response untouched when disabled', () {
      final original = Response.ok('body');
      final result = applyCorsHeaders(
        _request(origin: 'https://a.com'),
        original,
        const CorsOff(),
      );

      expect(result, same(original));
    });

    test('merges into an existing Vary instead of replacing it', () {
      final result = applyCorsHeaders(
        _request(origin: 'https://a.com'),
        Response.ok('x', headers: {'Vary': 'Accept-Encoding'}),
        const CorsReflectAny(),
      );

      expect(result.headers['vary'], 'Accept-Encoding, Origin');
    });

    test('dedupes Vary case-insensitively', () {
      final result = applyCorsHeaders(
        _request(origin: 'https://a.com'),
        Response.ok('x', headers: {'Vary': 'origin, Accept-Encoding'}),
        const CorsReflectAny(),
      );

      expect(result.headers['vary'], 'origin, Accept-Encoding');
    });

    test('leaves a wildcard Vary alone', () {
      final result = applyCorsHeaders(
        _request(origin: 'https://a.com'),
        Response.ok('x', headers: {'Vary': '*'}),
        const CorsReflectAny(),
      );

      expect(result.headers['vary'], '*');
    });

    test('preserves existing response headers', () {
      final result = applyCorsHeaders(
        _request(origin: 'https://a.com'),
        Response.ok('{}', headers: {'Content-Type': 'application/json'}),
        const CorsReflectAny(),
      );

      expect(result.headers['content-type'], 'application/json');
      expect(result.headers['access-control-allow-origin'], 'https://a.com');
    });
  });

  group('CorsConfig.resolve', () {
    test('onRequest default is off', () {
      const config = CorsConfig();
      expect(config.resolve(debugCorsEnabled: false), isA<CorsOff>());
    });

    test('callable default reflects any origin', () {
      // Node.js defaults callables to `cors: true`, i.e. reflect, not `*`.
      const config = CorsConfig(enabledByDefault: true);
      expect(config.resolve(debugCorsEnabled: false), isA<CorsReflectAny>());
    });

    test('a single origin collapses to a fixed header', () {
      const config = CorsConfig(option: Cors(['https://example.com']));
      expect(
        config.resolve(debugCorsEnabled: false),
        isA<CorsFixedOrigin>().having(
          (d) => d.origin,
          'origin',
          'https://example.com',
        ),
      );
    });

    test('several origins become a match list', () {
      const config = CorsConfig(
        option: Cors(['https://a.com', 'https://b.com']),
      );
      expect(config.resolve(debugCorsEnabled: false), isA<CorsMatchList>());
    });

    test('a lone star means the literal wildcard', () {
      expect(
        const CorsConfig(option: corsAnyOriginWildcard)
            .resolve(debugCorsEnabled: false),
        isA<CorsWildcard>(),
      );
    });

    test('corsAllowAnyOrigin means reflect', () {
      expect(
        const CorsConfig(option: corsAllowAnyOrigin)
            .resolve(debugCorsEnabled: false),
        isA<CorsReflectAny>(),
      );
    });

    test('a lone pattern stays dynamic rather than collapsing', () {
      const config = CorsConfig(option: Cors([CorsPattern('example')]));
      expect(config.resolve(debugCorsEnabled: false), isA<CorsMatchList>());
    });

    test('an empty list disables CORS', () {
      const config = CorsConfig(option: corsDisabled, enabledByDefault: true);
      expect(config.resolve(debugCorsEnabled: false), isA<CorsOff>());
    });

    test('emulator debug feature enables an unconfigured function', () {
      const config = CorsConfig();
      expect(config.resolve(debugCorsEnabled: true), isA<CorsReflectAny>());
    });

    test('emulator debug feature widens an explicit allow-list', () {
      const config = CorsConfig(option: Cors(['https://example.com']));
      expect(config.resolve(debugCorsEnabled: true), isA<CorsReflectAny>());
    });

    test('emulator debug feature respects an explicit opt-out', () {
      // Matches the Node.js SDK: `cors: false` stays off even under the
      // emulator, so local behaviour reproduces production.
      const config = CorsConfig(option: corsDisabled);
      expect(config.resolve(debugCorsEnabled: true), isA<CorsOff>());
    });

    test('disables CORS when the option throws instead of crashing', () {
      const config = CorsConfig(
        option: Cors.expression(_ThrowingExpression()),
        enabledByDefault: true,
      );

      expect(config.resolve(debugCorsEnabled: false), isA<CorsOff>());
    });

    test('resolves an expression to its runtime value', () {
      const config = CorsConfig(
        option: Cors.expression(
          LiteralExpression(<Object>['https://a.com', 'https://b.com']),
        ),
      );

      expect(config.resolve(debugCorsEnabled: false), isA<CorsMatchList>());
    });
  });
}

final class _ThrowingExpression extends Expression<List<Object>> {
  const _ThrowingExpression();

  @override
  List<Object> runtimeValue() => throw StateError('unavailable');

  @override
  String toCEL() => 'broken';
}
