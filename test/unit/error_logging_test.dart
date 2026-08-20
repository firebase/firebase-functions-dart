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

import 'package:firebase_functions/src/common/environment.dart';
import 'package:firebase_functions/src/firebase.dart';
import 'package:firebase_functions/src/https/https_namespace.dart';
import 'package:firebase_functions/src/pubsub/pubsub_namespace.dart';
import 'package:firebase_functions/src/scheduler/scheduler_namespace.dart';
import 'package:firebase_functions/src/server.dart';
import 'package:google_cloud_shelf/google_cloud_shelf.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    FirebaseEnv.mockEnvironment = {'FIREBASE_PROJECT': 'demo-test'};
  });

  group('HTTPS handler error logging integration', () {
    late Firebase firebase;
    late HttpsNamespace https;

    setUp(() {
      firebase = createFirebaseInternal();
      https = HttpsNamespace(firebase);
    });

    test(
      'onRequest: unexpected error returns 500 without sensitive details',
      () async {
        https.onRequest(name: 'crashEndpoint', (request) async {
          throw StateError('sensitive: connection string is postgres://...');
        });

        final handler = createTestHandler(firebase);
        final request = Request(
          'GET',
          Uri.parse('http://localhost/crashendpoint'),
        );
        final response = await handler(request);

        expect(response.statusCode, 500);
        final body = await response.readAsString();

        // Sensitive details are NOT in the response
        expect(body, isNot(contains('postgres://')));
        expect(body, isNot(contains('connection string')));
      },
    );

    test(
      'onRequest: HttpResponseException returns JSON when Accept header is application/json',
      () async {
        https.onRequest(name: 'knownErrorJson', (request) async {
          throw HttpResponseException.notFound(message: 'User 42 not found');
        });

        final handler = createTestHandler(firebase);
        final request = Request(
          'GET',
          Uri.parse('http://localhost/knownerrorjson'),
          headers: {'accept': 'application/json'},
        );
        final response = await handler(request);

        expect(response.statusCode, 404);
        expect(response.headers['content-type'], contains('application/json'));

        final body =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        final error = body['error'] as Map<String, dynamic>;
        expect(error['code'], 404);
        expect(error['status'], 'NOT_FOUND');
        expect(error['message'], 'User 42 not found');
      },
    );

    test(
      'onRequest: HttpResponseException returns text response when Accept header is not JSON',
      () async {
        https.onRequest(name: 'knownErrorText', (request) async {
          throw HttpResponseException.notFound(message: 'User 42 not found');
        });

        final handler = createTestHandler(firebase);
        final request = Request(
          'GET',
          Uri.parse('http://localhost/knownerrortext'),
        );
        final response = await handler(request);

        expect(response.statusCode, 404);
        final body = await response.readAsString();
        expect(body, contains('User 42 not found'));
      },
    );
  });

  group('Event handler error logging integration', () {
    late Firebase firebase;

    setUp(() {
      firebase = createFirebaseInternal();
    });

    test('PubSub: unexpected error returns 500 without details', () async {
      final pubsub = PubSubNamespace(firebase);
      pubsub.onMessagePublished(topic: 'test-topic', (event) async {
        throw Exception('sensitive: api key is sk-12345');
      });

      final cloudEvent = {
        'specversion': '1.0',
        'id': 'test-id',
        'source': '//pubsub.googleapis.com/projects/test/topics/test-topic',
        'type': 'google.cloud.pubsub.topic.v1.messagePublished',
        'time': '2024-01-01T00:00:00Z',
        'data': {
          'message': {
            'data': base64Encode(utf8.encode('test message')),
            'attributes': <String, String>{},
            'messageId': '123',
            'publishTime': '2024-01-01T00:00:00Z',
            'orderingKey': '',
          },
          'subscription': 'projects/test/subscriptions/test-sub',
        },
      };

      final handler = createTestHandler(firebase);
      final request = Request(
        'POST',
        Uri.parse('http://localhost/onmessagepublished-testtopic'),
        body: jsonEncode(cloudEvent),
        headers: {'content-type': 'application/json'},
      );
      final response = await handler(request);

      expect(response.statusCode, 500);
      final body = await response.readAsString();

      // Sensitive details are NOT in the response
      expect(body, isNot(contains('api key')));
      expect(body, isNot(contains('sk-12345')));
    });

    test('Scheduler: unexpected error returns 500 without details', () async {
      final scheduler = SchedulerNamespace(firebase);
      scheduler.onSchedule(schedule: '0 0 * * *', (event) async {
        throw Exception('sensitive: db password is hunter2');
      });

      final handler = createTestHandler(firebase);
      final request = Request(
        'POST',
        Uri.parse('http://localhost/onschedule-0-0'),
        headers: {'x-cloudscheduler-scheduletime': '2024-01-01T00:00:00Z'},
      );
      final response = await handler(request);

      expect(response.statusCode, 500);
      final body = await response.readAsString();

      // Sensitive details are NOT in the response
      expect(body, isNot(contains('db password')));
      expect(body, isNot(contains('hunter2')));
    });
  });
}
