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

import 'package:firebase_functions/src/server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('server', () {
    group('extractTraceId', () {
      test('extracts valid trace ID with span and option', () {
        const header = '4bf92f3577b34da6a3ce929d0e0e4736/12345;o=1';
        expect(extractTraceId(header), '4bf92f3577b34da6a3ce929d0e0e4736');
      });

      test('extracts valid trace ID with uppercase hex', () {
        const header = '4BF92F3577B34DA6A3CE929D0E0E4736/12345;o=1';
        expect(extractTraceId(header), '4BF92F3577B34DA6A3CE929D0E0E4736');
      });

      test('extracts valid trace ID without span or option', () {
        const header = '1234567890abcdef1234567890abcdef';
        expect(extractTraceId(header), '1234567890abcdef1234567890abcdef');
      });

      test('handles null and empty', () {
        expect(extractTraceId(null), isNull);
        expect(extractTraceId(''), isNull);
      });

      test('rejects malformed traces', () {
        // Too short
        expect(extractTraceId('1234/567;o=1'), isNull);

        // Too long
        expect(extractTraceId('1234567890abcdef1234567890abcdef0/5'), isNull);

        // Invalid hex
        expect(extractTraceId('1234567890xyzdef1234567890abcdef/5'), isNull);
      });
    });

    group('RunFunctionsOptions', () {
      test('defaults to null (no header)', () {
        const opts = RunFunctionsOptions();
        expect(opts.poweredByHeader, isNull);
      });

      test('accepts a custom header value', () {
        const opts = RunFunctionsOptions(poweredByHeader: 'MyApp/1.0');
        expect(opts.poweredByHeader, 'MyApp/1.0');
      });
    });

    group('corsHeadersFor', () {
      test('returns asterisk when allowedOrigins contains asterisk', () {
        final request = Request('GET', Uri.parse('http://localhost/test'));
        final headers = corsHeadersFor(request, ['*']);
        expect(headers['Access-Control-Allow-Origin'], '*');
      });

      test('echoes the Origin header if it matches allowedOrigins', () {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/test'),
          headers: {'origin': 'https://example.com'},
        );
        final headers = corsHeadersFor(request, ['https://example.com']);
        expect(headers['Access-Control-Allow-Origin'], 'https://example.com');
      });

      test('returns empty map if no match is found', () {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/test'),
          headers: {'origin': 'https://evil.com'},
        );
        final headers = corsHeadersFor(request, ['https://example.com']);
        expect(headers, isEmpty);
      });
    });
  });
}
