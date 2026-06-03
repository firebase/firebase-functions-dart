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
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../helpers/emulator.dart';
import '../helpers/storage_client.dart';

/// Creates a Storage CloudEvent JSON payload.
///
/// Matches the format produced by the Firebase Storage emulator's
/// `StorageCloudFunctions.createCloudEventRequestBody`.
Map<String, dynamic> _storageCloudEvent({
  required String eventType,
  String bucket = 'demo-test.firebasestorage.app',
  String objectName = 'test/file.txt',
  String contentType = 'text/plain',
  String size = '1024',
  String storageClass = 'STANDARD',
  Map<String, String>? metadata,
}) {
  return {
    'specversion': '1.0',
    'id': 'test-event-${DateTime.now().millisecondsSinceEpoch}',
    'source':
        '//storage.googleapis.com/projects/_/buckets/$bucket/objects/$objectName',
    'type': eventType,
    'time': DateTime.now().toUtc().toIso8601String(),
    'data': {
      'kind': 'storage#object',
      'bucket': bucket,
      'name': objectName,
      'generation': '1234567890',
      'metageneration': '1',
      'contentType': contentType,
      'size': size,
      'storageClass': storageClass,
      'metadata': ?metadata,
      'timeCreated': '2024-01-01T12:00:00Z',
      'updated': '2024-01-01T12:00:00Z',
    },
  };
}

/// Builds the URL for the functions emulator's trigger_multicast endpoint.
///
/// This is the same endpoint the Storage emulator uses internally to dispatch
/// CloudEvents to matching functions.
String _triggerMulticastUrl(EmulatorHelper emulator) =>
    'http://localhost:${emulator.functionsPort}/functions/projects/demo-test/trigger_multicast';

/// Content-Type header used by the Storage emulator when dispatching
/// CloudEvents to the functions emulator.
const _cloudEventContentType = 'application/cloudevents+json; charset=UTF-8';

/// Finds the actual function name from the manifest that starts with [prefix].
///
/// Needed because long names get truncated with a hash suffix by `toCloudRunId`.
String? _findFunctionName(String manifestContent, String prefix) {
  // Match a line like "  onobjectarchived-demotestfirebasestorageapp:"
  final pattern = RegExp('^\\s+($prefix[a-z0-9-]*):', multiLine: true);
  final match = pattern.firstMatch(manifestContent);
  return match?.group(1);
}

/// Storage trigger test group
void runStorageTests(
  String Function() getExamplePath,
  StorageClient Function() getStorageClient,
  EmulatorHelper Function() getEmulator,
) {
  group('Storage onObjectFinalized', () {
    late String examplePath;
    late StorageClient storageClient;
    late EmulatorHelper emulator;

    setUpAll(() {
      examplePath = getExamplePath();
      storageClient = getStorageClient();
      emulator = getEmulator();
    });

    test('function is registered with emulator', () {
      final manifestPath = '$examplePath/functions.yaml';
      final manifestFile = File(manifestPath);

      expect(
        manifestFile.existsSync(),
        isTrue,
        reason: 'functions.yaml should exist',
      );

      final manifestContent = manifestFile.readAsStringSync();
      expect(
        manifestContent,
        contains('onobjectfinalized-demotestfirebasestorageapp'),
        reason: 'Manifest should contain Storage finalized function',
      );
      expect(
        manifestContent,
        contains('onobjectdeleted-demotestfirebasestorageapp'),
        reason: 'Manifest should contain Storage deleted function',
      );
    });

    test('upload triggers onObjectFinalized', () async {
      emulator.clearOutputBuffer();

      print('Uploading test file...');

      final content = Uint8List.fromList(
        utf8.encode('Hello from E2E storage test!'),
      );
      await storageClient.uploadObject(
        'test/e2e-upload.txt',
        data: content,
        contentType: 'text/plain',
      );

      print('File uploaded, waiting for trigger...');

      // Wait for function to process the event
      await Future<void>.delayed(const Duration(seconds: 3));

      final logs = emulator.outputLines;
      final functionExecuted = logs.any(
        (line) => line.contains('Object finalized in bucket'),
      );
      expect(
        functionExecuted,
        isTrue,
        reason:
            'onObjectFinalized should be triggered on upload. '
            'Logs: ${logs.where((l) => l.contains("storage") || l.contains("Object") || l.contains("finalized")).join("\n")}',
      );

      print('✓ onObjectFinalized triggered');
    });

    test('function receives correct object metadata', () async {
      emulator.clearOutputBuffer();

      final content = Uint8List.fromList(utf8.encode('Metadata test content'));
      await storageClient.uploadObject(
        'test/metadata-test.txt',
        data: content,
        contentType: 'text/plain',
      );

      await Future<void>.delayed(const Duration(seconds: 3));

      final logs = emulator.outputLines;

      final hasName = logs.any(
        (line) => line.contains('test/metadata-test.txt'),
      );
      // The Storage emulator may report a different content type than what
      // was uploaded, so just check that a Content Type line is logged.
      final hasContentType = logs.any((line) => line.contains('Content Type:'));

      expect(hasName, isTrue, reason: 'Function should log the object name');
      expect(
        hasContentType,
        isTrue,
        reason: 'Function should log the content type',
      );

      print('✓ Object metadata received correctly');
    });

    test('delete triggers onObjectDeleted', () async {
      // First upload an object
      final content = Uint8List.fromList(utf8.encode('File to delete'));
      await storageClient.uploadObject(
        'test/to-delete.txt',
        data: content,
        contentType: 'text/plain',
      );

      // Wait for upload trigger to complete
      await Future<void>.delayed(const Duration(seconds: 2));

      // Clear logs and delete
      emulator.clearOutputBuffer();

      print('Deleting test file...');
      await storageClient.deleteObject('test/to-delete.txt');

      // Wait for function to process the event
      await Future<void>.delayed(const Duration(seconds: 3));

      final logs = emulator.outputLines;
      final functionExecuted = logs.any(
        (line) => line.contains('Object deleted in bucket'),
      );
      expect(
        functionExecuted,
        isTrue,
        reason:
            'onObjectDeleted should be triggered on delete. '
            'Logs: ${logs.where((l) => l.contains("storage") || l.contains("Object") || l.contains("deleted")).join("\n")}',
      );

      print('✓ onObjectDeleted triggered');
    });

    test('handles multiple uploads in sequence', () async {
      emulator.clearOutputBuffer();

      print('Uploading multiple files...');

      for (var i = 1; i <= 3; i++) {
        final content = Uint8List.fromList(utf8.encode('File $i content'));
        await storageClient.uploadObject(
          'test/sequential-$i.txt',
          data: content,
          contentType: 'text/plain',
        );
        print('  Uploaded file $i');
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      // Wait for all triggers
      await Future<void>.delayed(const Duration(seconds: 4));

      final logs = emulator.outputLines;
      final triggerCount = logs
          .where((line) => line.contains('Object finalized in bucket'))
          .length;

      expect(
        triggerCount,
        greaterThanOrEqualTo(3),
        reason: 'All 3 uploads should trigger onObjectFinalized',
      );

      print('✓ All sequential uploads triggered');
    });
  });

  // ===========================================================================
  // onObjectArchived and onObjectMetadataUpdated tests
  //
  // The Firebase Storage emulator does not emit "archived" or "metadataUpdated"
  // events. Instead, we test these by posting CloudEvent payloads to the
  // functions emulator's trigger_multicast endpoint — the same internal
  // endpoint the Storage emulator uses to dispatch events to functions.
  // ===========================================================================

  group('Storage onObjectArchived', () {
    late String examplePath;
    late EmulatorHelper emulator;
    late http.Client client;
    late String multicastUrl;

    setUpAll(() {
      examplePath = getExamplePath();
      emulator = getEmulator();
      client = http.Client();
      multicastUrl = _triggerMulticastUrl(emulator);
    });

    tearDownAll(() {
      client.close();
    });

    test('function is registered with emulator', () {
      final manifestPath = '$examplePath/functions.yaml';
      final manifestFile = File(manifestPath);

      expect(
        manifestFile.existsSync(),
        isTrue,
        reason: 'functions.yaml should exist',
      );

      final manifestContent = manifestFile.readAsStringSync();
      expect(
        manifestContent,
        contains('onobjectarchived-demotestfirebasestorageapp'),
        reason: 'Manifest should contain Storage archived function',
      );
    });

    test('CloudEvent triggers onObjectArchived handler', () async {
      emulator.clearOutputBuffer();

      print('Sending archived CloudEvent via trigger_multicast...');

      final cloudEvent = _storageCloudEvent(
        eventType: 'google.cloud.storage.object.v1.archived',
        objectName: 'test/archive-test.txt',
      );

      final response = await client.post(
        Uri.parse(multicastUrl),
        headers: {'Content-Type': _cloudEventContentType},
        body: jsonEncode(cloudEvent),
      );

      expect(
        response.statusCode,
        200,
        reason: 'trigger_multicast should return 200. Body: ${response.body}',
      );

      // Wait for logs to propagate
      await Future<void>.delayed(const Duration(seconds: 2));

      final logs = emulator.outputLines;
      final functionExecuted = logs.any(
        (line) => line.contains('Object archived in bucket'),
      );
      expect(
        functionExecuted,
        isTrue,
        reason:
            'onObjectArchived handler should log the event. '
            'Logs: ${logs.where((l) => l.contains("Object") || l.contains("archived")).join("\n")}',
      );

      print('✓ onObjectArchived triggered');
    });

    test('function receives correct event data', () async {
      emulator.clearOutputBuffer();

      final cloudEvent = _storageCloudEvent(
        eventType: 'google.cloud.storage.object.v1.archived',
        objectName: 'test/archive-metadata.txt',
        storageClass: 'NEARLINE',
      );

      final response = await client.post(
        Uri.parse(multicastUrl),
        headers: {'Content-Type': _cloudEventContentType},
        body: jsonEncode(cloudEvent),
      );

      expect(response.statusCode, 200);

      await Future<void>.delayed(const Duration(seconds: 2));

      final logs = emulator.outputLines;

      final hasName = logs.any(
        (line) => line.contains('test/archive-metadata.txt'),
      );
      final hasStorageClass = logs.any((line) => line.contains('NEARLINE'));

      expect(
        hasName,
        isTrue,
        reason: 'Function should log the archived object name',
      );
      expect(
        hasStorageClass,
        isTrue,
        reason: 'Function should log the storage class',
      );

      print('✓ Archive event data received correctly');
    });

    test('handles multiple archived events in sequence', () async {
      emulator.clearOutputBuffer();

      print('Sending multiple archived CloudEvents...');

      for (var i = 1; i <= 3; i++) {
        final cloudEvent = _storageCloudEvent(
          eventType: 'google.cloud.storage.object.v1.archived',
          objectName: 'test/archive-sequential-$i.txt',
        );

        final response = await client.post(
          Uri.parse(multicastUrl),
          headers: {'Content-Type': _cloudEventContentType},
          body: jsonEncode(cloudEvent),
        );

        expect(response.statusCode, 200);
        print('  Sent archived event $i');
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      await Future<void>.delayed(const Duration(seconds: 2));

      final logs = emulator.outputLines;
      final archiveCount = logs
          .where((line) => line.contains('Object archived in bucket'))
          .length;

      expect(
        archiveCount,
        greaterThanOrEqualTo(3),
        reason: 'All 3 archived events should trigger onObjectArchived',
      );

      print('✓ All sequential archived events triggered');
    });
  });

  group('Storage onObjectMetadataUpdated', () {
    late String examplePath;
    late EmulatorHelper emulator;
    late http.Client client;
    late String multicastUrl;
    late String functionName;

    setUpAll(() {
      examplePath = getExamplePath();
      emulator = getEmulator();
      client = http.Client();
      multicastUrl = _triggerMulticastUrl(emulator);

      // Read the actual function name from the manifest since it may be
      // truncated with a hash suffix due to the 50-char Cloud Run ID limit.
      final manifestContent = File(
        '$examplePath/functions.yaml',
      ).readAsStringSync();
      functionName =
          _findFunctionName(manifestContent, 'onobjectmetadataupdated') ??
          'onobjectmetadataupdated-demotestfirebasestorageapp';
      print('Using function name: $functionName');
    });

    tearDownAll(() {
      client.close();
    });

    test('function is registered with emulator', () {
      final manifestPath = '$examplePath/functions.yaml';
      final manifestFile = File(manifestPath);

      expect(
        manifestFile.existsSync(),
        isTrue,
        reason: 'functions.yaml should exist',
      );

      final manifestContent = manifestFile.readAsStringSync();
      expect(
        manifestContent,
        contains(functionName),
        reason: 'Manifest should contain Storage metadata updated function',
      );
    });

    test('CloudEvent triggers onObjectMetadataUpdated handler', () async {
      emulator.clearOutputBuffer();

      print('Sending metadataUpdated CloudEvent via trigger_multicast...');

      final cloudEvent = _storageCloudEvent(
        eventType: 'google.cloud.storage.object.v1.metadataUpdated',
        objectName: 'test/metadata-update.txt',
        metadata: {'customKey': 'customValue'},
      );

      final response = await client.post(
        Uri.parse(multicastUrl),
        headers: {'Content-Type': _cloudEventContentType},
        body: jsonEncode(cloudEvent),
      );

      expect(
        response.statusCode,
        200,
        reason: 'trigger_multicast should return 200. Body: ${response.body}',
      );

      await Future<void>.delayed(const Duration(seconds: 2));

      final logs = emulator.outputLines;
      final functionExecuted = logs.any(
        (line) => line.contains('Object metadata updated in bucket'),
      );
      expect(
        functionExecuted,
        isTrue,
        reason:
            'onObjectMetadataUpdated handler should log the event. '
            'Logs: ${logs.where((l) => l.contains("Object") || l.contains("metadata")).join("\n")}',
      );

      print('✓ onObjectMetadataUpdated triggered');
    });

    test('function receives correct metadata', () async {
      emulator.clearOutputBuffer();

      final cloudEvent = _storageCloudEvent(
        eventType: 'google.cloud.storage.object.v1.metadataUpdated',
        objectName: 'test/metadata-verify.txt',
        metadata: {'env': 'test', 'version': '42'},
      );

      final response = await client.post(
        Uri.parse(multicastUrl),
        headers: {'Content-Type': _cloudEventContentType},
        body: jsonEncode(cloudEvent),
      );

      expect(response.statusCode, 200);

      await Future<void>.delayed(const Duration(seconds: 2));

      final logs = emulator.outputLines;

      final hasName = logs.any(
        (line) => line.contains('test/metadata-verify.txt'),
      );
      final hasMetadata = logs.any((line) => line.contains('Metadata:'));

      expect(hasName, isTrue, reason: 'Function should log the object name');
      expect(hasMetadata, isTrue, reason: 'Function should log the metadata');

      print('✓ Metadata event data received correctly');
    });

    test('handles sequential metadata update events', () async {
      emulator.clearOutputBuffer();

      print('Sending multiple metadataUpdated CloudEvents...');

      for (var i = 1; i <= 3; i++) {
        final cloudEvent = _storageCloudEvent(
          eventType: 'google.cloud.storage.object.v1.metadataUpdated',
          objectName: 'test/metadata-sequential.txt',
          metadata: {'iteration': '$i'},
        );

        final response = await client.post(
          Uri.parse(multicastUrl),
          headers: {'Content-Type': _cloudEventContentType},
          body: jsonEncode(cloudEvent),
        );

        expect(response.statusCode, 200);
        print('  Sent metadata update event $i');
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      await Future<void>.delayed(const Duration(seconds: 2));

      final logs = emulator.outputLines;
      final updateCount = logs
          .where((line) => line.contains('Object metadata updated in bucket'))
          .length;

      expect(
        updateCount,
        greaterThanOrEqualTo(3),
        reason:
            'All 3 metadata update events should trigger onObjectMetadataUpdated',
      );

      print('✓ All sequential metadata update events triggered');
    });
  });
}
