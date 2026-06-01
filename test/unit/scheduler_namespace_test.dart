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

import 'package:firebase_functions/src/common/environment.dart';
import 'package:firebase_functions/src/common/options.dart';
import 'package:firebase_functions/src/firebase.dart';
import 'package:firebase_functions/src/scheduler/options.dart';
import 'package:firebase_functions/src/scheduler/scheduled_event.dart';
import 'package:firebase_functions/src/scheduler/scheduler_namespace.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

// Helper to find function by name
FirebaseFunctionDeclaration? _findFunction(Firebase firebase, String name) {
  try {
    return firebase.functions.firstWhere((f) => f.name == name.toLowerCase());
  } catch (e) {
    return null;
  }
}

void main() {
  setUpAll(() {
    FirebaseEnv.mockEnvironment = {'FIREBASE_PROJECT': 'demo-test'};
  });

  group('SchedulerNamespace', () {
    late Firebase firebase;
    late SchedulerNamespace scheduler;

    setUp(() {
      firebase = createFirebaseInternal();
      scheduler = SchedulerNamespace(firebase);
    });

    group('onSchedule', () {
      test('registers function with firebase', () {
        scheduler.onSchedule(schedule: '0 0 * * *', (event) async {});

        // Function name: schedule '0 0 * * *' becomes 'onschedule-0-0'
        expect(_findFunction(firebase, 'onschedule-0-0'), isNotNull);
      });

      test('generates correct function name from schedule', () {
        scheduler.onSchedule(schedule: '*/5 * * * *', (event) async {});

        // '*/5 * * * *' -> 'onschedule-5' (removes *, /)
        expect(_findFunction(firebase, 'onschedule-5'), isNotNull);
      });

      test('handler receives scheduled event', () async {
        ScheduledEvent? receivedEvent;

        scheduler.onSchedule(schedule: '0 0 * * *', (event) async {
          receivedEvent = event;
        });

        final func = _findFunction(firebase, 'onschedule-0-0')!;
        final request = Request(
          'POST',
          Uri.parse('http://localhost/onschedule-0-0'),
          headers: {
            'x-cloudscheduler-jobname':
                'projects/test/locations/us-central1/jobs/myjob',
            'x-cloudscheduler-scheduletime': '2024-01-01T00:00:00Z',
          },
        );
        final response = await func.handler(request);

        expect(response.statusCode, 200);
        expect(receivedEvent, isNotNull);
        expect(
          receivedEvent!.jobName,
          'projects/test/locations/us-central1/jobs/myjob',
        );
        expect(receivedEvent!.scheduleTime, '2024-01-01T00:00:00Z');
      });

      test('handles missing job name header', () async {
        ScheduledEvent? receivedEvent;

        scheduler.onSchedule(schedule: '0 0 * * *', (event) async {
          receivedEvent = event;
        });

        final func = _findFunction(firebase, 'onschedule-0-0')!;
        final request = Request(
          'POST',
          Uri.parse('http://localhost/onschedule-0-0'),
          headers: {'x-cloudscheduler-scheduletime': '2024-01-01T00:00:00Z'},
        );
        final response = await func.handler(request);

        expect(response.statusCode, 200);
        expect(receivedEvent, isNotNull);
        expect(receivedEvent!.jobName, isNull);
        expect(receivedEvent!.scheduleTime, '2024-01-01T00:00:00Z');
      });

      test('uses current time when schedule time header missing', () async {
        ScheduledEvent? receivedEvent;

        scheduler.onSchedule(schedule: '0 0 * * *', (event) async {
          receivedEvent = event;
        });

        final func = _findFunction(firebase, 'onschedule-0-0')!;
        final request = Request(
          'POST',
          Uri.parse('http://localhost/onschedule-0-0'),
          headers: {},
        );
        final response = await func.handler(request);

        expect(response.statusCode, 200);
        expect(receivedEvent, isNotNull);
        expect(receivedEvent!.scheduleTime, isNotNull);
        // Should be a valid ISO8601 timestamp
        expect(
          () => DateTime.parse(receivedEvent!.scheduleTime),
          returnsNormally,
        );
      });

      test('returns 200 on success', () async {
        scheduler.onSchedule(schedule: '0 0 * * *', (event) async {
          // Success - do nothing
        });

        final func = _findFunction(firebase, 'onschedule-0-0')!;
        final request = Request(
          'POST',
          Uri.parse('http://localhost/onschedule-0-0'),
          headers: {'x-cloudscheduler-scheduletime': '2024-01-01T00:00:00Z'},
        );
        final response = await func.handler(request);

        expect(response.statusCode, 200);
      });

      test('returns 500 on handler error without leaking details', () async {
        scheduler.onSchedule(schedule: '0 0 * * *', (event) async {
          throw Exception('Handler error');
        });

        final func = _findFunction(firebase, 'onschedule-0-0')!;
        final request = Request(
          'POST',
          Uri.parse('http://localhost/onschedule-0-0'),
          headers: {'x-cloudscheduler-scheduletime': '2024-01-01T00:00:00Z'},
        );
        final response = await func.handler(request);

        expect(response.statusCode, 500);
        final body = await response.readAsString();
        expect(body, isNot(contains('Handler error')));
      });

      test('accepts schedule options', () {
        scheduler.onSchedule(
          schedule: '0 0 * * *',
          options: const ScheduleOptions(
            timeZone: TimeZone('America/New_York'),
            retryConfig: RetryConfig(
              retryCount: RetryCount(3),
              maxRetrySeconds: MaxRetrySeconds(60),
            ),
          ),
          (event) async {},
        );

        expect(_findFunction(firebase, 'onschedule-0-0'), isNotNull);
      });

      test('handles case-insensitive headers', () async {
        ScheduledEvent? receivedEvent;

        scheduler.onSchedule(schedule: '0 0 * * *', (event) async {
          receivedEvent = event;
        });

        final func = _findFunction(firebase, 'onschedule-0-0')!;
        final request = Request(
          'POST',
          Uri.parse('http://localhost/onschedule-0-0'),
          headers: {
            'X-CloudScheduler-JobName': 'test-job',
            'X-CloudScheduler-ScheduleTime': '2024-01-01T00:00:00Z',
          },
        );
        final response = await func.handler(request);

        expect(response.statusCode, 200);
        expect(receivedEvent, isNotNull);
        expect(receivedEvent!.jobName, 'test-job');
      });
    });
  });

  group('ScheduledEvent', () {
    test('creates from headers', () {
      final event = ScheduledEvent.fromHeaders({
        'x-cloudscheduler-jobname': 'test-job',
        'x-cloudscheduler-scheduletime': '2024-01-01T00:00:00Z',
      });

      expect(event.jobName, 'test-job');
      expect(event.scheduleTime, '2024-01-01T00:00:00Z');
    });

    test('handles missing job name', () {
      final event = ScheduledEvent.fromHeaders({
        'x-cloudscheduler-scheduletime': '2024-01-01T00:00:00Z',
      });

      expect(event.jobName, isNull);
      expect(event.scheduleTime, '2024-01-01T00:00:00Z');
    });

    test('uses current time when schedule time missing', () {
      final before = DateTime.now().toUtc();
      final event = ScheduledEvent.fromHeaders({});
      final after = DateTime.now().toUtc();

      expect(event.jobName, isNull);
      final eventTime = DateTime.parse(event.scheduleTime);
      expect(
        eventTime.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(eventTime.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });

    test('scheduleDateTime returns parsed DateTime', () {
      final event = const ScheduledEvent(
        jobName: 'test',
        scheduleTime: '2024-01-15T10:30:00Z',
      );

      final dt = event.scheduleDateTime;
      expect(dt.year, 2024);
      expect(dt.month, 1);
      expect(dt.day, 15);
      expect(dt.hour, 10);
      expect(dt.minute, 30);
    });

    test('toString returns readable format', () {
      final event = const ScheduledEvent(
        jobName: 'my-job',
        scheduleTime: '2024-01-01T00:00:00Z',
      );

      expect(
        event.toString(),
        'ScheduledEvent(jobName: my-job, scheduleTime: 2024-01-01T00:00:00Z)',
      );
    });
  });

  group('ScheduleOptions', () {
    test('extends GlobalOptions', () {
      const options = ScheduleOptions(
        memory: Memory(MemoryOption.mb512),
        timeoutSeconds: TimeoutSeconds(60),
      );

      expect(options.memory, isA<Memory>());
      expect(options.timeoutSeconds, isA<TimeoutSeconds>());
    });

    test('supports timeZone', () {
      const options = ScheduleOptions(timeZone: TimeZone('America/New_York'));

      expect(options.timeZone, isNotNull);
      expect(options.timeZone!.runtimeValue(), 'America/New_York');
    });

    test('supports retryConfig', () {
      const options = ScheduleOptions(
        retryConfig: RetryConfig(
          retryCount: RetryCount(5),
          maxRetrySeconds: MaxRetrySeconds(3600),
          minBackoffSeconds: MinBackoffSeconds(5),
          maxBackoffSeconds: MaxBackoffSeconds(60),
          maxDoublings: MaxDoublings(16),
        ),
      );

      expect(options.retryConfig, isNotNull);
      expect(options.retryConfig!.retryCount!.runtimeValue(), 5);
      expect(options.retryConfig!.maxRetrySeconds!.runtimeValue(), 3600);
      expect(options.retryConfig!.minBackoffSeconds!.runtimeValue(), 5);
      expect(options.retryConfig!.maxBackoffSeconds!.runtimeValue(), 60);
      expect(options.retryConfig!.maxDoublings!.runtimeValue(), 16);
    });
  });
}
