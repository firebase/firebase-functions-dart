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

// ignore_for_file: avoid_dynamic_calls

import 'dart:async';
import 'dart:convert';

import 'package:firebase_functions/src/common/environment.dart';
import 'package:firebase_functions/src/firebase.dart';
import 'package:firebase_functions/src/https/callable.dart';
import 'package:firebase_functions/src/https/error.dart';
import 'package:firebase_functions/src/https/https_namespace.dart';
import 'package:firebase_functions/src/https/options.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

// Helper to find function by name (uses kebab-case Cloud Run ID)
FirebaseFunctionDeclaration? _findFunction(Firebase firebase, String name) {
  try {
    return firebase.functions.firstWhere((f) => f.name == name);
  } catch (e) {
    return null;
  }
}

void main() {
  setUpAll(() {
    FirebaseEnv.mockEnvironment = {'FIREBASE_PROJECT': 'demo-test'};
  });

  group('HttpsNamespace', () {
    late Firebase firebase;
    late HttpsNamespace https;

    setUp(() {
      firebase = createFirebaseInternal();
      https = HttpsNamespace(firebase);
    });

    group('onRequest', () {
      test('registers function with firebase', () {
        https.onRequest(
          name: 'testFunction',
          (request) async => Response.ok('Hello'),
        );

        expect(_findFunction(firebase, 'testfunction'), isNotNull);
      });

      test('handler receives request and returns response', () async {
        https.onRequest(
          name: 'testFunction',
          (request) async => Response.ok('Hello, World!'),
        );

        final func = _findFunction(firebase, 'testfunction')!;
        final request = Request(
          'GET',
          Uri.parse('http://localhost/testfunction'),
        );
        final response = await func.handler(request);

        expect(response.statusCode, 200);
        expect(await response.readAsString(), 'Hello, World!');
      });

      test('catches HttpsError and returns proper error response', () async {
        https.onRequest(name: 'errorFunction', (request) async {
          throw NotFoundError('Resource not found');
        });

        final func = _findFunction(firebase, 'errorfunction')!;
        final request = Request(
          'GET',
          Uri.parse('http://localhost/errorfunction'),
        );
        final response = await func.handler(request);

        expect(response.statusCode, 404);
        expect(response.headers['Content-Type'], 'application/json');

        final body = jsonDecode(await response.readAsString());
        expect(body['error']['status'], 'NOT_FOUND');
        expect(body['error']['message'], 'Resource not found');
      });

      test('catches unexpected errors and returns internal error', () async {
        https.onRequest(name: 'crashFunction', (request) async {
          throw Exception('Unexpected crash');
        });

        final func = _findFunction(firebase, 'crashfunction')!;
        final request = Request(
          'GET',
          Uri.parse('http://localhost/crashfunction'),
        );
        final response = await func.handler(request);

        expect(response.statusCode, 500);
        expect(response.headers['Content-Type'], 'application/json');

        final body = jsonDecode(await response.readAsString());
        expect(body['error']['status'], 'INTERNAL');
      });

      test('marks function as external', () {
        https.onRequest(
          name: 'externalFunction',
          (request) async => Response.ok('OK'),
        );

        final func = _findFunction(firebase, 'externalfunction')!;
        expect(func.external, isTrue);
      });

      test('uses correct HTTP status codes for different errors', () async {
        https.onRequest(name: 'unauthorizedFunction', (request) async {
          throw UnauthenticatedError('Not logged in');
        });

        final func = _findFunction(firebase, 'unauthorizedfunction')!;
        final request = Request('GET', Uri.parse('http://localhost/test'));
        final response = await func.handler(request);

        expect(response.statusCode, 401);
      });
    });

    group('onCall', () {
      Request createCallableRequest({
        Map<String, dynamic> data = const {},
        Map<String, String> headers = const {},
      }) {
        final body = jsonEncode({'data': data});
        return Request(
          'POST',
          Uri.parse('http://localhost/testfunction'),
          headers: {'content-type': 'application/json', ...headers},
          body: body,
        );
      }

      test('registers function with firebase', () {
        https.onCall(
          name: 'callableFunction',
          (request, response) async => CallableResult('OK'),
        );

        expect(_findFunction(firebase, 'callablefunction'), isNotNull);
      });

      test('handler returns wrapped result', () async {
        https.onCall(name: 'greetFunction', (request, response) async {
          final data = request.data as Map<String, dynamic>;
          final name = data['name'] as String;
          return CallableResult({'message': 'Hello, $name!'});
        });

        final func = _findFunction(firebase, 'greetfunction')!;
        final request = createCallableRequest(data: {'name': 'World'});
        final response = await func.handler(request);

        expect(response.statusCode, 200);
        expect(response.headers['content-type'], 'application/json');

        final body = jsonDecode(await response.readAsString());
        expect(body['result'], {'message': 'Hello, World!'});
      });

      test('validates request is POST', () async {
        https.onCall(
          name: 'postOnlyFunction',
          (request, response) async => CallableResult('OK'),
        );

        final func = _findFunction(firebase, 'postonlyfunction')!;
        final request = Request(
          'GET',
          Uri.parse('http://localhost/postonlyfunction'),
          headers: {'content-type': 'application/json'},
        );
        final response = await func.handler(request);

        expect(response.statusCode, 400);
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['status'], 'INVALID_ARGUMENT');
      });

      test('validates content-type is application/json', () async {
        https.onCall(
          name: 'jsonOnlyFunction',
          (request, response) async => CallableResult('OK'),
        );

        final func = _findFunction(firebase, 'jsononlyfunction')!;
        final request = Request(
          'POST',
          Uri.parse('http://localhost/jsononlyfunction'),
          headers: {'content-type': 'text/plain'},
          body: '{"data": "test"}',
        );
        final response = await func.handler(request);

        expect(response.statusCode, 400);
      });

      test('catches HttpsError and returns proper status', () async {
        https.onCall(name: 'errorFunction', (request, response) async {
          throw PermissionDeniedError('Not authorized');
        });

        final func = _findFunction(firebase, 'errorfunction')!;
        final request = createCallableRequest();
        final response = await func.handler(request);

        expect(response.statusCode, 403);
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['status'], 'PERMISSION_DENIED');
        expect(body['error']['message'], 'Not authorized');
      });

      test('catches unexpected errors as internal errors', () async {
        https.onCall(name: 'crashFunction', (request, response) async {
          throw StateError('Something broke');
        });

        final func = _findFunction(firebase, 'crashfunction')!;
        final request = createCallableRequest();
        final response = await func.handler(request);

        expect(response.statusCode, 500);
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['status'], 'INTERNAL');
      });

      test('returns JSON when client does not accept SSE', () async {
        https.onCall(name: 'nonStreamFunction', (request, response) async {
          return CallableResult('result');
        });

        final func = _findFunction(firebase, 'nonstreamfunction')!;
        final request = createCallableRequest();
        final response = await func.handler(request);

        expect(response.statusCode, 200);
        expect(response.headers['content-type'], 'application/json');

        final body = jsonDecode(await response.readAsString());
        expect(body['result'], 'result');
      });

      test('JsonResult returns Map data correctly', () async {
        https.onCall(name: 'jsonResultFunction', (request, response) async {
          return JsonResult({'status': 'ok', 'count': 42});
        });

        final func = _findFunction(firebase, 'jsonresultfunction')!;
        final request = createCallableRequest();
        final response = await func.handler(request);

        final body = jsonDecode(await response.readAsString());
        expect(body['result'], {'status': 'ok', 'count': 42});
      });

      group('streaming handling', () {
        test('catches HttpsError and returns SSE error', () async {
          https.onCall(name: 'streamErrorFunction', (request, response) async {
            throw InvalidArgumentError('Invalid data');
          });

          final func = _findFunction(firebase, 'streamerrorfunction')!;
          final request = createCallableRequest(
            headers: {'accept': 'text/event-stream'},
          );
          final response = await func.handler(request);

          expect(response.statusCode, 200);
          expect(response.headers['content-type'], 'text/event-stream');

          final body = await response.readAsString();
          final jsonStr = body.substring('data: '.length).trim();
          expect(jsonDecode(jsonStr), {
            'error': {'status': 'INVALID_ARGUMENT', 'message': 'Invalid data'},
          });
        });

        test(
          'catches unexpected exceptions and returns SSE internal error',
          () async {
            https.onCall(name: 'streamCrashFunction', (
              request,
              response,
            ) async {
              throw Exception('Unexpected crash');
            });

            final func = _findFunction(firebase, 'streamcrashfunction')!;
            final request = createCallableRequest(
              headers: {'accept': 'text/event-stream'},
            );
            final response = await func.handler(request);

            expect(response.statusCode, 200);
            expect(response.headers['content-type'], 'text/event-stream');

            final body = await response.readAsString();
            final jsonStr = body.substring('data: '.length).trim();
            expect(jsonDecode(jsonStr), {
              'error': {
                'status': 'INTERNAL',
                'message': 'An unexpected error occurred.',
              },
            });
          },
        );

        test('success streaming returns SSE data', () async {
          https.onCall(name: 'streamSuccessFunction', (
            request,
            response,
          ) async {
            return CallableResult('success');
          });

          final func = _findFunction(firebase, 'streamsuccessfunction')!;
          final request = createCallableRequest(
            headers: {'accept': 'text/event-stream'},
          );
          final response = await func.handler(request);

          expect(response.statusCode, 200);
          expect(response.headers['content-type'], 'text/event-stream');

          final body = await response.readAsString();
          final jsonStr = body.substring('data: '.length).trim();
          expect(jsonDecode(jsonStr), {'result': 'success'});
        });

        test('catches error emitted by stream and returns SSE error', () async {
          https.onCall(name: 'streamStreamErrorFunction', (
            request,
            response,
          ) async {
            final controller = StreamController<CallableResult<String>>();
            response.stream(controller.stream);

            controller.add(CallableResult('part 1'));
            controller.addError(InvalidArgumentError('Invalid part 2'));
            unawaited(controller.close());

            await Future<void>.delayed(const Duration(milliseconds: 100));
            return CallableResult('done');
          });

          final func = _findFunction(firebase, 'streamstreamerrorfunction')!;
          final request = createCallableRequest(
            headers: {'accept': 'text/event-stream'},
          );
          final response = await func.handler(request);

          expect(response.statusCode, 200);
          final body = await response.readAsString();
          final events = body
              .split('\n\n')
              .where((e) => e.trim().isNotEmpty)
              .toList();
          expect(events.length, 2);
          final decodedEvents = events
              .map((e) => jsonDecode(e.substring('data: '.length)))
              .toList();
          expect(decodedEvents, contains(equals({'message': 'part 1'})));
          expect(
            decodedEvents,
            contains(
              equals({
                'error': {
                  'status': 'INVALID_ARGUMENT',
                  'message': 'Invalid part 2',
                },
              }),
            ),
          );
        });

        test(
          'true background streaming works with Stream.fromIterable',
          () async {
            https.onCall(name: 'bgStreamFunction', (request, response) async {
              final source = Stream.fromIterable([
                CallableResult('item 1'),
                CallableResult('item 2'),
              ]);
              response.stream(source);

              return CallableResult('done');
            });

            final func = _findFunction(firebase, 'bgstreamfunction')!;
            final request = createCallableRequest(
              headers: {'accept': 'text/event-stream'},
            );
            final response = await func.handler(request);

            expect(response.statusCode, 200);

            final body = await response.readAsString();
            final events = body
                .split('\n\n')
                .where((e) => e.trim().isNotEmpty)
                .toList();
            expect(events.length, 3);
            final decodedEvents = events
                .map((e) => jsonDecode(e.substring('data: '.length)))
                .toList();
            expect(decodedEvents, contains(equals({'message': 'item 1'})));
            expect(decodedEvents, contains(equals({'message': 'item 2'})));
            expect(decodedEvents, contains(equals({'result': 'done'})));
          },
        );
      });
    });

    group('onCallWithData', () {
      Request createCallableRequest({
        Map<String, dynamic> data = const {},
        Map<String, String> headers = const {},
      }) {
        final body = jsonEncode({'data': data});
        return Request(
          'POST',
          Uri.parse('http://localhost/testfunction'),
          headers: {'content-type': 'application/json', ...headers},
          body: body,
        );
      }

      test('registers function with firebase', () {
        https.onCallWithData<_GreetRequest, _GreetResponse>(
          name: 'typedFunction',
          fromJson: _GreetRequest.fromJson,
          (request, response) async {
            return _GreetResponse('Hello, ${request.data.name}!');
          },
        );

        expect(_findFunction(firebase, 'typedfunction'), isNotNull);
      });

      test('deserializes input using fromJson', () async {
        https.onCallWithData<_GreetRequest, String>(
          name: 'typedFunction',
          fromJson: _GreetRequest.fromJson,
          (request, response) async {
            expect(request.data, isA<_GreetRequest>());
            expect(request.data.name, 'World');
            return 'Hello, ${request.data.name}!';
          },
        );

        final func = _findFunction(firebase, 'typedfunction')!;
        final request = createCallableRequest(data: {'name': 'World'});
        final response = await func.handler(request);

        expect(response.statusCode, 200);
        final body = jsonDecode(await response.readAsString());
        expect(body['result'], 'Hello, World!');
      });

      test('returns typed output correctly', () async {
        https.onCallWithData<_GreetRequest, _GreetResponse>(
          name: 'typedOutputFunction',
          fromJson: _GreetRequest.fromJson,
          (request, response) async {
            return _GreetResponse('Hello, ${request.data.name}!');
          },
        );

        final func = _findFunction(firebase, 'typedoutputfunction')!;
        final request = createCallableRequest(data: {'name': 'World'});
        final response = await func.handler(request);

        expect(response.statusCode, 200);
        final body = jsonDecode(await response.readAsString());
        // _GreetResponse is encoded via its toJson method
        expect(body['result'], {'message': 'Hello, World!'});
      });

      test('validates request is POST', () async {
        https.onCallWithData<_GreetRequest, String>(
          name: 'postOnlyTypedFunction',
          fromJson: _GreetRequest.fromJson,
          (request, response) async => 'OK',
        );

        final func = _findFunction(firebase, 'postonlytypedfunction')!;
        final request = Request(
          'GET',
          Uri.parse('http://localhost/postonlytypedfunction'),
          headers: {'content-type': 'application/json'},
        );
        final response = await func.handler(request);

        expect(response.statusCode, 400);
      });

      test('catches HttpsError and returns proper status', () async {
        https.onCallWithData<_GreetRequest, String>(
          name: 'errorTypedFunction',
          fromJson: _GreetRequest.fromJson,
          (request, response) async {
            throw InvalidArgumentError('Name cannot be empty');
          },
        );

        final func = _findFunction(firebase, 'errortypedfunction')!;
        final request = createCallableRequest(data: {'name': ''});
        final response = await func.handler(request);

        expect(response.statusCode, 400);
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['status'], 'INVALID_ARGUMENT');
        expect(body['error']['message'], 'Name cannot be empty');
      });
    });

    group('Options', () {
      test('HttpsOptions can be provided', () {
        https.onRequest(
          name: 'optionsFunction',
          options: const HttpsOptions(cors: Cors(['https://example.com'])),
          (request) async => Response.ok('OK'),
        );

        final func = _findFunction(firebase, 'optionsfunction')!;
        expect(func.allowedOrigins, ['https://example.com']);
      });

      test('CallableOptions can be provided', () {
        https.onCall(
          name: 'callableOptionsFunction',
          options: const CallableOptions(
            heartBeatIntervalSeconds: HeartBeatIntervalSeconds(30),
          ),
          (request, response) async => CallableResult('OK'),
        );

        expect(_findFunction(firebase, 'callableoptionsfunction'), isNotNull);
      });

      test('CallableOptions can be provided passing allowedOrigins', () {
        https.onCall(
          name: 'callableOptionsFunctionWithOrigins',
          options: const CallableOptions(cors: Cors(['https://example.com'])),
          (request, response) async => CallableResult('OK'),
        );

        final func = _findFunction(
          firebase,
          'callableoptionsfunctionwithorigins',
        )!;
        expect(func.allowedOrigins, ['https://example.com']);
      });

      test(
        'onCall defaults allowedOrigins to [*] when no cors option given',
        () {
          https.onCall(
            name: 'callableNoCors',
            (request, response) async => CallableResult('OK'),
          );

          final func = _findFunction(firebase, 'callablenocors')!;
          expect(func.allowedOrigins, ['*']);
        },
      );

      test(
        'onCallWithData defaults allowedOrigins to [*] when no cors option given',
        () {
          https.onCallWithData<_GreetRequest, String>(
            name: 'typedNoCors',
            fromJson: _GreetRequest.fromJson,
            (request, response) async => 'OK',
          );

          final func = _findFunction(firebase, 'typednocors')!;
          expect(func.allowedOrigins, ['*']);
        },
      );
    });
  });
}

// Test helper classes
class _GreetRequest {
  _GreetRequest(this.name);

  factory _GreetRequest.fromJson(Map<String, dynamic> json) {
    return _GreetRequest(json['name'] as String);
  }

  final String name;
}

class _GreetResponse {
  _GreetResponse(this.message);

  final String message;

  Map<String, dynamic> toJson() => {'message': message};

  @override
  String toString() => message;
}
