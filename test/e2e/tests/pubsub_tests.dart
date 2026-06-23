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

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/emulator.dart';
import '../helpers/pubsub_client.dart';

/// Pub/Sub test group
void runPubSubTests(
  String Function() getExamplePath,
  PubSubClient Function() getPubSubClient,
  EmulatorHelper Function() getEmulator,
) {
  group('Pub/Sub onMessagePublished', () {
    late String examplePath;
    late PubSubClient pubsubClient;
    late EmulatorHelper emulator;

    setUpAll(() {
      examplePath = getExamplePath();
      pubsubClient = getPubSubClient();
      emulator = getEmulator();
    });

    test('function is registered with emulator', () {
      // Verify the function was loaded in manifest
      final manifestPath = '$examplePath/functions.yaml';
      final manifestFile = File(manifestPath);

      // Debug output
      print('DEBUG pubsub: examplePath = $examplePath');
      print('DEBUG pubsub: manifestPath = $manifestPath');
      print(
        'DEBUG pubsub: manifestFile.existsSync() = ${manifestFile.existsSync()}',
      );

      expect(
        manifestFile.existsSync(),
        isTrue,
        reason: 'functions.yaml should exist',
      );

      final manifestContent = manifestFile.readAsStringSync();
      expect(
        manifestContent,
        contains('onmessagepublished-mytopic'),
        reason: 'Manifest should contain Pub/Sub function',
      );
    });

    test('publishes message and triggers function', () async {
      // Clear logs to isolate this test
      emulator.clearOutputBuffer();

      print('Publishing message to my-topic...');

      // Publish a test message
      final response = await pubsubClient.publishMessage(
        'my-topic',
        data: 'Hello from E2E test!',
        attributes: {'testAttribute': 'testValue', 'source': 'e2e-test'},
      );

      print('Message published with ID: ${response.messageId}');

      // Wait for function to process the message
      await Future<void>.delayed(const Duration(seconds: 2));

      // Verify function was triggered by checking for function output
      // Note: Can't use verifyFunctionExecution() because shared Dart runtime
      // confuses the emulator about which function is executing
      final logs = emulator.outputLines;
      final functionExecuted = logs.any(
        (line) => line.contains('Received Pub/Sub message'),
      );
      expect(
        functionExecuted,
        isTrue,
        reason: 'Pub/Sub function should be triggered and log message receipt',
      );

      print('✓ Function execution verified in logs');
    });

    test('function receives correct message data', () async {
      // Clear logs
      emulator.clearOutputBuffer();

      const testMessage = 'Test message with special chars: åäö 123 !@#';
      print('Publishing message: "$testMessage"');

      // Publish message
      await pubsubClient.publishMessage('my-topic', data: testMessage);

      // Wait for processing
      await Future<void>.delayed(const Duration(seconds: 2));

      // Verify the function logged the message data
      final logs = emulator.outputLines;
      final foundMessage = logs.any((line) => line.contains(testMessage));

      expect(
        foundMessage,
        isTrue,
        reason: 'Function should receive and log the message data',
      );

      print('✓ Message data received correctly');
    });

    test('function receives message attributes', () async {
      // Clear logs
      emulator.clearOutputBuffer();

      print('Publishing message with custom attributes...');

      // Publish message with attributes
      await pubsubClient.publishMessage(
        'my-topic',
        data: 'Message with attributes',
        attributes: {
          'userId': '12345',
          'action': 'test',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      // Wait for processing
      await Future<void>.delayed(const Duration(seconds: 2));

      // Verify attributes are in logs
      final logs = emulator.outputLines;
      final hasUserId = logs.any((line) => line.contains('userId'));
      final hasAction = logs.any((line) => line.contains('action'));

      expect(
        hasUserId && hasAction,
        isTrue,
        reason: 'Function should receive and log message attributes',
      );

      print('✓ Message attributes received correctly');
    });

    test('handles multiple messages in sequence', () async {
      // Clear logs
      emulator.clearOutputBuffer();

      print('Publishing multiple messages...');

      // Publish multiple messages
      for (var i = 1; i <= 3; i++) {
        await pubsubClient.publishMessage('my-topic', data: 'Message $i');
        print('  Published message $i');

        // Small delay between messages
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      // Wait for all to process
      await Future<void>.delayed(const Duration(seconds: 3));

      // Verify all messages were processed
      final logs = emulator.outputLines;
      final message1 = logs.any((line) => line.contains('Message 1'));
      final message2 = logs.any((line) => line.contains('Message 2'));
      final message3 = logs.any((line) => line.contains('Message 3'));

      expect(
        message1 && message2 && message3,
        isTrue,
        reason: 'All messages should be processed',
      );

      print('✓ All messages processed successfully');
    });

    test('handles messages with empty attributes', () async {
      // Clear logs
      emulator.clearOutputBuffer();

      print('Publishing message without attributes...');

      // Publish message without attributes
      await pubsubClient.publishMessage(
        'my-topic',
        data: 'Message without attributes',
      );

      // Wait for processing
      await Future<void>.delayed(const Duration(seconds: 2));

      // Verify function was triggered by checking for function output
      // Note: Can't use verifyFunctionExecution() because shared Dart runtime
      // confuses the emulator about which function is executing
      final logs = emulator.outputLines;
      final functionExecuted = logs.any(
        (line) => line.contains('Message without attributes'),
      );

      expect(
        functionExecuted,
        isTrue,
        reason: 'Function should handle messages without attributes',
      );

      print('✓ Message without attributes handled correctly');
    });

    test('verifies CloudEvent structure in logs', () async {
      // Clear logs
      emulator.clearOutputBuffer();

      print('Publishing message to verify CloudEvent format...');

      // Publish message
      await pubsubClient.publishMessage('my-topic', data: 'CloudEvent test');

      // Wait for processing
      await Future<void>.delayed(const Duration(seconds: 2));

      // Check for CloudEvent-related log entries
      final logs = emulator.outputLines;

      // The function logs message ID and publishTime, which are CloudEvent properties
      final hasMessageId = logs.any((line) => line.contains('ID:'));
      final hasPublishTime = logs.any((line) => line.contains('Published:'));

      expect(
        hasMessageId && hasPublishTime,
        isTrue,
        reason: 'CloudEvent structure should be present in function logs',
      );

      print('✓ CloudEvent structure verified');
    });
  });
}
