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
import 'package:firebase_functions/src/storage/storage_event.dart';
import 'package:firebase_functions/src/storage/storage_namespace.dart';
import 'package:firebase_functions/src/storage/storage_object_data.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'shared_utils.dart';

// Helper to find function by name
FirebaseFunctionDeclaration? _findFunction(Firebase firebase, String name) {
  try {
    return firebase.functions.firstWhere((f) => f.name == name.toLowerCase());
  } catch (e) {
    return null;
  }
}

/// Creates a mock CloudEvent POST request for Storage.
Request _createStorageRequest({
  String eventType = 'google.cloud.storage.object.v1.finalized',
  String bucket = 'my-bucket',
  String objectName = 'path/to/file.txt',
  String? contentType = 'text/plain',
  String? size = '1024',
  String? storageClass = 'STANDARD',
  Map<String, String>? metadata,
}) {
  final data = <String, dynamic>{
    'bucket': bucket,
    'name': objectName,
    'generation': '1234567890',
    'metageneration': '1',
    'contentType': ?contentType,
    'size': ?size,
    'storageClass': ?storageClass,
    'metadata': ?metadata,
    'timeCreated': '2024-01-01T12:00:00Z',
    'updated': '2024-01-01T12:00:00Z',
  };

  final cloudEvent = {
    'specversion': '1.0',
    'id': 'test-event-123',
    'source': '//storage.googleapis.com/projects/_/buckets/$bucket',
    'type': eventType,
    'time': '2024-01-01T12:00:00Z',
    'subject': 'objects/$objectName',
    'data': data,
  };

  return Request(
    'POST',
    Uri.parse('http://localhost/onobjectfinalized-mybucket'),
    body: jsonEncode(cloudEvent),
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  setUpAll(() {
    FirebaseEnv.mockEnvironment = {'FIREBASE_PROJECT': 'demo-test'};
  });

  group('StorageNamespace', () {
    late Firebase firebase;
    late StorageNamespace storage;

    setUp(() {
      firebase = createFirebaseInternal();
      storage = StorageNamespace(firebase);
    });

    group('onObjectFinalized', () {
      test('registers function with firebase', () {
        storage.onObjectFinalized(bucket: 'my-bucket', (event) async {});

        expect(
          _findFunction(firebase, 'onobjectfinalized-mybucket'),
          isNotNull,
        );
      });

      test('registered function is not external', () {
        storage.onObjectFinalized(bucket: 'my-bucket', (event) async {});

        final func = _findFunction(firebase, 'onobjectfinalized-mybucket')!;
        expect(func.external, isFalse);
      });

      test('handler receives StorageEvent with StorageObjectData', () async {
        StorageEvent? receivedEvent;

        storage.onObjectFinalized(bucket: 'my-bucket', (event) async {
          receivedEvent = event;
        });

        final func = _findFunction(firebase, 'onobjectfinalized-mybucket')!;
        final request = _createStorageRequest(
          objectName: 'uploads/image.png',
          contentType: 'image/png',
          size: '2048',
        );
        final response = await func.handler(request);

        expect(response.statusCode, 200);
        expect(receivedEvent, isNotNull);
        expect(receivedEvent!.data, isNotNull);
        expect(receivedEvent!.data!.bucket, 'my-bucket');
        expect(receivedEvent!.data!.name, 'uploads/image.png');
        expect(receivedEvent!.data!.contentType, 'image/png');
        expect(receivedEvent!.data!.size, '2048');
      });

      test('handler receives correct CloudEvent metadata', () async {
        StorageEvent? receivedEvent;

        storage.onObjectFinalized(bucket: 'my-bucket', (event) async {
          receivedEvent = event;
        });

        final func = _findFunction(firebase, 'onobjectfinalized-mybucket')!;
        final response = await func.handler(_createStorageRequest());

        expect(response.statusCode, 200);
        expect(receivedEvent, isNotNull);
        expect(receivedEvent!.id, 'test-event-123');
        expect(
          receivedEvent!.source,
          '//storage.googleapis.com/projects/_/buckets/my-bucket',
        );
        expect(receivedEvent!.type, 'google.cloud.storage.object.v1.finalized');
        expect(receivedEvent!.specversion, '1.0');
        expect(receivedEvent!.subject, 'objects/path/to/file.txt');
      });

      test('bucket getter returns correct bucket', () async {
        StorageEvent? receivedEvent;

        storage.onObjectFinalized(bucket: 'my-bucket', (event) async {
          receivedEvent = event;
        });

        final func = _findFunction(firebase, 'onobjectfinalized-mybucket')!;
        await func.handler(_createStorageRequest());

        expect(receivedEvent!.bucket, 'my-bucket');
      });
    });

    group('onObjectArchived', () {
      test('registers function with firebase', () {
        storage.onObjectArchived(bucket: 'my-bucket', (event) async {});

        expect(_findFunction(firebase, 'onobjectarchived-mybucket'), isNotNull);
      });

      test('handler receives StorageEvent', () async {
        StorageEvent? receivedEvent;

        storage.onObjectArchived(bucket: 'my-bucket', (event) async {
          receivedEvent = event;
        });

        final func = _findFunction(firebase, 'onobjectarchived-mybucket')!;
        final request = _createStorageRequest(
          eventType: 'google.cloud.storage.object.v1.archived',
        );
        final response = await func.handler(request);

        expect(response.statusCode, 200);
        expect(receivedEvent, isNotNull);
        expect(receivedEvent!.data!.bucket, 'my-bucket');
      });
    });

    group('onObjectDeleted', () {
      test('registers function with firebase', () {
        storage.onObjectDeleted(bucket: 'my-bucket', (event) async {});

        expect(_findFunction(firebase, 'onobjectdeleted-mybucket'), isNotNull);
      });

      test('handler receives StorageEvent', () async {
        StorageEvent? receivedEvent;

        storage.onObjectDeleted(bucket: 'my-bucket', (event) async {
          receivedEvent = event;
        });

        final func = _findFunction(firebase, 'onobjectdeleted-mybucket')!;
        final request = _createStorageRequest(
          eventType: 'google.cloud.storage.object.v1.deleted',
        );
        final response = await func.handler(request);

        expect(response.statusCode, 200);
        expect(receivedEvent, isNotNull);
        expect(receivedEvent!.data!.bucket, 'my-bucket');
      });
    });

    group('onObjectMetadataUpdated', () {
      test('registers function with firebase', () {
        storage.onObjectMetadataUpdated(bucket: 'my-bucket', (event) async {});

        expect(
          _findFunction(firebase, 'onobjectmetadataupdated-mybucket'),
          isNotNull,
        );
      });

      test('handler receives StorageEvent with metadata', () async {
        StorageEvent? receivedEvent;

        storage.onObjectMetadataUpdated(bucket: 'my-bucket', (event) async {
          receivedEvent = event;
        });

        final func = _findFunction(
          firebase,
          'onobjectmetadataupdated-mybucket',
        )!;
        final request = _createStorageRequest(
          eventType: 'google.cloud.storage.object.v1.metadataUpdated',
          metadata: {'key1': 'value1', 'key2': 'value2'},
        );
        final response = await func.handler(request);

        expect(response.statusCode, 200);
        expect(receivedEvent, isNotNull);
        expect(receivedEvent!.data!.metadata, {
          'key1': 'value1',
          'key2': 'value2',
        });
      });
    });

    group('function naming', () {
      test('sanitizes bucket name by removing hyphens', () {
        storage.onObjectFinalized(bucket: 'my-test-bucket', (event) async {});

        expect(
          _findFunction(firebase, 'onobjectfinalized-mytestbucket'),
          isNotNull,
        );
      });

      test('sanitizes bucket name with dots', () {
        storage.onObjectFinalized(
          bucket: 'demo-test.firebasestorage.app',
          (event) async {},
        );

        expect(
          _findFunction(
            firebase,
            'onobjectfinalized-demotestfirebasestorageapp',
          ),
          isNotNull,
        );
      });
    });

    group('error handling', () {
      test('returns 200 on success', () async {
        storage.onObjectFinalized(bucket: 'my-bucket', (event) async {});

        final func = _findFunction(firebase, 'onobjectfinalized-mybucket')!;
        final response = await func.handler(_createStorageRequest());

        expect(response.statusCode, 200);
      });

      test('returns 500 on handler error without leaking details', () async {
        storage.onObjectFinalized(bucket: 'my-bucket', (event) async {
          throw Exception('Handler error');
        });

        final handler = findHandler(firebase, 'onobjectfinalized-mybucket');
        final response = await handler(_createStorageRequest());

        expect(response.statusCode, 500);
        final body = await response.readAsString();
        expect(body, isNot(contains('Handler error')));
      });

      test('returns 500 when handler throws FormatException', () async {
        storage.onObjectFinalized(bucket: 'my-bucket', (event) async {
          throw const FormatException('User-level format error');
        });

        final handler = findHandler(firebase, 'onobjectfinalized-mybucket');
        final response = await handler(_createStorageRequest());

        expect(response.statusCode, 500);
        final body = await response.readAsString();
        expect(body, isNot(contains('Invalid CloudEvent')));
      });

      test('returns 400 for invalid CloudEvent', () async {
        storage.onObjectFinalized(bucket: 'my-bucket', (event) async {});

        final func = _findFunction(firebase, 'onobjectfinalized-mybucket')!;
        final request = Request(
          'POST',
          Uri.parse('http://localhost/onobjectfinalized-mybucket'),
          body: 'not json',
          headers: {'content-type': 'application/json'},
        );
        final response = await func.handler(request);

        expect(response.statusCode, 400);
      });

      test('returns 400 for wrong event type', () async {
        storage.onObjectFinalized(bucket: 'my-bucket', (event) async {});

        final func = _findFunction(firebase, 'onobjectfinalized-mybucket')!;
        final request = Request(
          'POST',
          Uri.parse('http://localhost/onobjectfinalized-mybucket'),
          body: jsonEncode({
            'specversion': '1.0',
            'id': 'test',
            'source': 'test',
            'type': 'google.cloud.pubsub.topic.v1.messagePublished',
            'time': '2024-01-01T00:00:00Z',
            'data': {
              'bucket': 'my-bucket',
              'name': 'test.txt',
              'generation': '1',
              'metageneration': '1',
            },
          }),
          headers: {'content-type': 'application/json'},
        );
        final response = await func.handler(request);

        expect(response.statusCode, 400);
        final body = await response.readAsString();
        expect(body, contains('Invalid event type for Storage'));
      });
    });
  });

  group('StorageObjectData', () {
    test('parses from JSON with all fields', () {
      final json = {
        'bucket': 'test-bucket',
        'name': 'path/to/file.txt',
        'generation': '1234567890',
        'metageneration': '2',
        'cacheControl': 'public, max-age=3600',
        'componentCount': 3,
        'contentDisposition': 'attachment',
        'contentEncoding': 'gzip',
        'contentLanguage': 'en',
        'contentType': 'text/plain',
        'crc32c': 'AAAAAA==',
        'customerEncryption': {
          'encryptionAlgorithm': 'AES256',
          'keySha256': 'abc123',
        },
        'etag': 'CJC/4t6x4PACEAE=',
        'id': 'test-bucket/path/to/file.txt/1234567890',
        'kind': 'storage#object',
        'md5Hash': 'rL0Y20zC+Fzt72VPzMSk2A==',
        'mediaLink': 'https://storage.googleapis.com/download',
        'metadata': {'key1': 'value1'},
        'selfLink':
            'https://storage.googleapis.com/storage/v1/b/test-bucket/o/file',
        'size': '1024',
        'storageClass': 'STANDARD',
        'timeCreated': '2024-01-01T12:00:00Z',
        'timeDeleted': '2024-06-01T12:00:00Z',
        'timeStorageClassUpdated': '2024-01-01T12:00:00Z',
        'updated': '2024-03-01T12:00:00Z',
      };

      final data = StorageObjectData.fromJson(json);

      expect(data.bucket, 'test-bucket');
      expect(data.name, 'path/to/file.txt');
      expect(data.generation, '1234567890');
      expect(data.metageneration, '2');
      expect(data.cacheControl, 'public, max-age=3600');
      expect(data.componentCount, 3);
      expect(data.contentDisposition, 'attachment');
      expect(data.contentEncoding, 'gzip');
      expect(data.contentLanguage, 'en');
      expect(data.contentType, 'text/plain');
      expect(data.crc32c, 'AAAAAA==');
      expect(data.customerEncryption, isNotNull);
      expect(data.customerEncryption!.encryptionAlgorithm, 'AES256');
      expect(data.customerEncryption!.keySha256, 'abc123');
      expect(data.etag, 'CJC/4t6x4PACEAE=');
      expect(data.id, 'test-bucket/path/to/file.txt/1234567890');
      expect(data.kind, 'storage#object');
      expect(data.md5Hash, 'rL0Y20zC+Fzt72VPzMSk2A==');
      expect(data.mediaLink, 'https://storage.googleapis.com/download');
      expect(data.metadata, {'key1': 'value1'});
      expect(data.selfLink, contains('test-bucket'));
      expect(data.size, '1024');
      expect(data.storageClass, 'STANDARD');
      expect(data.timeCreated, DateTime.utc(2024, 1, 1, 12));
      expect(data.timeDeleted, DateTime.utc(2024, 6, 1, 12));
      expect(data.timeStorageClassUpdated, DateTime.utc(2024, 1, 1, 12));
      expect(data.updated, DateTime.utc(2024, 3, 1, 12));
    });

    test('parses from JSON with minimal fields', () {
      final json = {
        'bucket': 'test-bucket',
        'name': 'file.txt',
        'generation': '1',
        'metageneration': '1',
      };

      final data = StorageObjectData.fromJson(json);

      expect(data.bucket, 'test-bucket');
      expect(data.name, 'file.txt');
      expect(data.generation, '1');
      expect(data.metageneration, '1');
      expect(data.contentType, isNull);
      expect(data.size, isNull);
      expect(data.metadata, isNull);
      expect(data.customerEncryption, isNull);
      expect(data.timeCreated, isNull);
      expect(data.timeDeleted, isNull);
    });

    test('converts to JSON', () {
      final data = const StorageObjectData(
        bucket: 'test-bucket',
        name: 'file.txt',
        generation: '1',
        metageneration: '1',
        contentType: 'text/plain',
        size: '512',
        metadata: {'key': 'value'},
      );

      final json = data.toJson();

      expect(json['bucket'], 'test-bucket');
      expect(json['name'], 'file.txt');
      expect(json['generation'], '1');
      expect(json['metageneration'], '1');
      expect(json['contentType'], 'text/plain');
      expect(json['size'], '512');
      expect(json['metadata'], {'key': 'value'});
      // Optional null fields should not be included
      expect(json.containsKey('cacheControl'), isFalse);
      expect(json.containsKey('customerEncryption'), isFalse);
      expect(json.containsKey('timeDeleted'), isFalse);
    });

    test('round-trips through JSON', () {
      final original = StorageObjectData(
        bucket: 'my-bucket',
        name: 'path/to/file.txt',
        generation: '123',
        metageneration: '2',
        contentType: 'application/json',
        size: '4096',
        storageClass: 'NEARLINE',
        timeCreated: DateTime.utc(2024),
        updated: DateTime.utc(2024, 6),
      );

      final json = original.toJson();
      final restored = StorageObjectData.fromJson(json);

      expect(restored.bucket, original.bucket);
      expect(restored.name, original.name);
      expect(restored.generation, original.generation);
      expect(restored.metageneration, original.metageneration);
      expect(restored.contentType, original.contentType);
      expect(restored.size, original.size);
      expect(restored.storageClass, original.storageClass);
      expect(restored.timeCreated, original.timeCreated);
      expect(restored.updated, original.updated);
    });
  });

  group('CustomerEncryption', () {
    test('parses from JSON', () {
      final json = {
        'encryptionAlgorithm': 'AES256',
        'keySha256': 'abc123def456',
      };

      final encryption = CustomerEncryption.fromJson(json);

      expect(encryption.encryptionAlgorithm, 'AES256');
      expect(encryption.keySha256, 'abc123def456');
    });

    test('handles missing fields with defaults', () {
      final encryption = CustomerEncryption.fromJson(<String, dynamic>{});

      expect(encryption.encryptionAlgorithm, '');
      expect(encryption.keySha256, '');
    });

    test('converts to JSON', () {
      const encryption = CustomerEncryption(
        encryptionAlgorithm: 'AES256',
        keySha256: 'sha256hash',
      );

      final json = encryption.toJson();

      expect(json['encryptionAlgorithm'], 'AES256');
      expect(json['keySha256'], 'sha256hash');
    });
  });

  group('StorageEvent', () {
    test('fromJson creates event with StorageObjectData', () {
      final json = {
        'specversion': '1.0',
        'id': 'event-123',
        'source': '//storage.googleapis.com/projects/_/buckets/test-bucket',
        'type': 'google.cloud.storage.object.v1.finalized',
        'time': '2024-01-01T12:00:00Z',
        'subject': 'objects/path/to/file.txt',
        'data': {
          'bucket': 'test-bucket',
          'name': 'path/to/file.txt',
          'generation': '1',
          'metageneration': '1',
          'contentType': 'text/plain',
        },
      };

      final event = StorageEvent.fromJson(json);

      expect(event.id, 'event-123');
      expect(event.source, contains('test-bucket'));
      expect(event.type, 'google.cloud.storage.object.v1.finalized');
      expect(event.subject, 'objects/path/to/file.txt');
      expect(event.data, isNotNull);
      expect(event.data!.bucket, 'test-bucket');
      expect(event.data!.name, 'path/to/file.txt');
      expect(event.data!.contentType, 'text/plain');
      expect(event.bucket, 'test-bucket');
    });
  });
}
