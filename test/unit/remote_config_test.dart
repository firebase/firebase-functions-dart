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

import 'package:firebase_functions/src/common/cloud_event.dart';
import 'package:firebase_functions/src/common/environment.dart';
import 'package:firebase_functions/src/firebase.dart';
import 'package:firebase_functions/src/remote_config/config_update_data.dart';
import 'package:firebase_functions/src/remote_config/remote_config_namespace.dart';
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

/// Creates a mock CloudEvent POST request for Remote Config.
Request _createRemoteConfigRequest({
  int versionNumber = 1,
  String updateOrigin = 'CONSOLE',
  String updateType = 'INCREMENTAL_UPDATE',
  String description = 'Test update',
  int? rollbackSource,
}) {
  final data = <String, dynamic>{
    'versionNumber': versionNumber,
    'updateTime': '2024-01-01T12:00:00Z',
    'updateUser': {
      'name': 'Test User',
      'email': 'test@example.com',
      'imageUrl': 'https://example.com/photo.png',
    },
    'description': description,
    'updateOrigin': updateOrigin,
    'updateType': updateType,
    'rollbackSource': ?rollbackSource,
  };

  final cloudEvent = {
    'specversion': '1.0',
    'id': 'test-event-123',
    'source': '//firebaseremoteconfig.googleapis.com/projects/test-project',
    'type': 'google.firebase.remoteconfig.remoteConfig.v1.updated',
    'time': '2024-01-01T12:00:00Z',
    'data': data,
  };

  return Request(
    'POST',
    Uri.parse('http://localhost/onconfigupdated'),
    body: jsonEncode(cloudEvent),
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  setUpAll(() {
    FirebaseEnv.mockEnvironment = {'FIREBASE_PROJECT': 'demo-test'};
  });

  group('RemoteConfigNamespace', () {
    late Firebase firebase;
    late RemoteConfigNamespace remoteConfig;

    setUp(() {
      firebase = createFirebaseInternal();
      remoteConfig = RemoteConfigNamespace(firebase);
    });

    group('onConfigUpdated', () {
      test('registers function with firebase', () {
        remoteConfig.onConfigUpdated((event) async {});

        expect(_findFunction(firebase, 'onconfigupdated'), isNotNull);
      });

      test('registered function is not external', () {
        remoteConfig.onConfigUpdated((event) async {});

        final func = _findFunction(firebase, 'onconfigupdated')!;
        expect(func.external, isFalse);
      });

      test('handler receives ConfigUpdateData', () async {
        CloudEvent<ConfigUpdateData>? receivedEvent;

        remoteConfig.onConfigUpdated((event) async {
          receivedEvent = event;
        });

        final func = _findFunction(firebase, 'onconfigupdated')!;
        final request = _createRemoteConfigRequest(
          versionNumber: 42,
          description: 'My config update',
        );
        final response = await func.handler(request);

        expect(response.statusCode, 200);
        expect(receivedEvent, isNotNull);
        expect(receivedEvent!.data, isNotNull);
        expect(receivedEvent!.data!.versionNumber, 42);
        expect(receivedEvent!.data!.description, 'My config update');
        expect(receivedEvent!.data!.updateUser.email, 'test@example.com');
        expect(receivedEvent!.data!.updateUser.name, 'Test User');
        expect(
          receivedEvent!.data!.updateUser.imageUrl,
          'https://example.com/photo.png',
        );
      });

      test('handler receives correct CloudEvent metadata', () async {
        CloudEvent<ConfigUpdateData>? receivedEvent;

        remoteConfig.onConfigUpdated((event) async {
          receivedEvent = event;
        });

        final func = _findFunction(firebase, 'onconfigupdated')!;
        final response = await func.handler(_createRemoteConfigRequest());

        expect(response.statusCode, 200);
        expect(receivedEvent, isNotNull);
        expect(receivedEvent!.id, 'test-event-123');
        expect(
          receivedEvent!.source,
          '//firebaseremoteconfig.googleapis.com/projects/test-project',
        );
        expect(
          receivedEvent!.type,
          'google.firebase.remoteconfig.remoteConfig.v1.updated',
        );
        expect(receivedEvent!.specversion, '1.0');
      });

      test('handler receives update origin', () async {
        CloudEvent<ConfigUpdateData>? receivedEvent;

        remoteConfig.onConfigUpdated((event) async {
          receivedEvent = event;
        });

        final func = _findFunction(firebase, 'onconfigupdated')!;
        final response = await func.handler(
          _createRemoteConfigRequest(updateOrigin: 'REST_API'),
        );

        expect(response.statusCode, 200);
        expect(receivedEvent!.data!.updateOrigin, ConfigUpdateOrigin.restApi);
      });

      test('handler receives update type', () async {
        CloudEvent<ConfigUpdateData>? receivedEvent;

        remoteConfig.onConfigUpdated((event) async {
          receivedEvent = event;
        });

        final func = _findFunction(firebase, 'onconfigupdated')!;
        final response = await func.handler(
          _createRemoteConfigRequest(updateType: 'FORCED_UPDATE'),
        );

        expect(response.statusCode, 200);
        expect(receivedEvent!.data!.updateType, ConfigUpdateType.forcedUpdate);
      });

      test('handler receives rollback source when present', () async {
        CloudEvent<ConfigUpdateData>? receivedEvent;

        remoteConfig.onConfigUpdated((event) async {
          receivedEvent = event;
        });

        final func = _findFunction(firebase, 'onconfigupdated')!;
        final response = await func.handler(
          _createRemoteConfigRequest(updateType: 'ROLLBACK', rollbackSource: 5),
        );

        expect(response.statusCode, 200);
        expect(receivedEvent!.data!.updateType, ConfigUpdateType.rollback);
        expect(receivedEvent!.data!.rollbackSource, 5);
      });

      test('rollbackSource is null when not present', () async {
        CloudEvent<ConfigUpdateData>? receivedEvent;

        remoteConfig.onConfigUpdated((event) async {
          receivedEvent = event;
        });

        final func = _findFunction(firebase, 'onconfigupdated')!;
        final response = await func.handler(_createRemoteConfigRequest());

        expect(response.statusCode, 200);
        expect(receivedEvent!.data!.rollbackSource, isNull);
      });

      test('returns 200 on success', () async {
        remoteConfig.onConfigUpdated((event) async {});

        final func = _findFunction(firebase, 'onconfigupdated')!;
        final response = await func.handler(_createRemoteConfigRequest());

        expect(response.statusCode, 200);
      });

      test('returns 500 on handler error without leaking details', () async {
        remoteConfig.onConfigUpdated((event) async {
          throw Exception('Handler error');
        });

        final handler = findHandler(firebase, 'onconfigupdated');
        final response = await handler(_createRemoteConfigRequest());

        expect(response.statusCode, 500);
        final body = await response.readAsString();
        expect(body, isNot(contains('Handler error')));
      });

      test('returns 400 for invalid CloudEvent', () async {
        remoteConfig.onConfigUpdated((event) async {});

        final func = _findFunction(firebase, 'onconfigupdated')!;
        final request = Request(
          'POST',
          Uri.parse('http://localhost/onconfigupdated'),
          body: 'not json',
          headers: {'content-type': 'application/json'},
        );
        final response = await func.handler(request);

        expect(response.statusCode, 400);
      });

      test('returns 400 for wrong event type', () async {
        remoteConfig.onConfigUpdated((event) async {});

        final func = _findFunction(firebase, 'onconfigupdated')!;
        final request = Request(
          'POST',
          Uri.parse('http://localhost/onconfigupdated'),
          body: jsonEncode({
            'specversion': '1.0',
            'id': 'test',
            'source': 'test',
            'type': 'google.cloud.pubsub.topic.v1.messagePublished',
            'time': '2024-01-01T00:00:00Z',
            'data': <String, dynamic>{},
          }),
          headers: {'content-type': 'application/json'},
        );
        final response = await func.handler(request);

        expect(response.statusCode, 400);
        final body = await response.readAsString();
        expect(body, contains('Invalid event type for Remote Config'));
      });
    });
  });

  group('ConfigUpdateData', () {
    test('parses from JSON', () {
      final json = {
        'versionNumber': 42,
        'updateTime': '2024-01-01T12:00:00Z',
        'updateUser': {
          'name': 'Test User',
          'email': 'test@example.com',
          'imageUrl': 'https://example.com/photo.png',
        },
        'description': 'Test update',
        'updateOrigin': 'CONSOLE',
        'updateType': 'INCREMENTAL_UPDATE',
      };

      final data = ConfigUpdateData.fromJson(json);

      expect(data.versionNumber, 42);
      expect(data.updateTime, DateTime.utc(2024, 1, 1, 12));
      expect(data.updateUser.name, 'Test User');
      expect(data.updateUser.email, 'test@example.com');
      expect(data.updateUser.imageUrl, 'https://example.com/photo.png');
      expect(data.description, 'Test update');
      expect(data.updateOrigin, ConfigUpdateOrigin.console);
      expect(data.updateType, ConfigUpdateType.incrementalUpdate);
      expect(data.rollbackSource, isNull);
    });

    test('parses rollback data', () {
      final json = {
        'versionNumber': 10,
        'updateTime': '2024-06-15T08:30:00Z',
        'updateUser': {
          'name': 'Admin',
          'email': 'admin@example.com',
          'imageUrl': '',
        },
        'description': 'Rolling back to version 5',
        'updateOrigin': 'CONSOLE',
        'updateType': 'ROLLBACK',
        'rollbackSource': 5,
      };

      final data = ConfigUpdateData.fromJson(json);

      expect(data.updateType, ConfigUpdateType.rollback);
      expect(data.rollbackSource, 5);
    });

    test('converts to JSON', () {
      final data = ConfigUpdateData(
        versionNumber: 1,
        updateTime: DateTime.utc(2024, 1, 1, 12),
        updateUser: const ConfigUser(
          name: 'Test',
          email: 'test@test.com',
          imageUrl: '',
        ),
        description: 'Desc',
        updateOrigin: ConfigUpdateOrigin.restApi,
        updateType: ConfigUpdateType.forcedUpdate,
      );

      final json = data.toJson();

      expect(json['versionNumber'], 1);
      expect(json['updateOrigin'], 'REST_API');
      expect(json['updateType'], 'FORCED_UPDATE');
      expect(json.containsKey('rollbackSource'), isFalse);
    });

    test('converts rollback to JSON', () {
      final data = ConfigUpdateData(
        versionNumber: 10,
        updateTime: DateTime.utc(2024, 6, 15),
        updateUser: const ConfigUser(
          name: 'Admin',
          email: 'admin@test.com',
          imageUrl: '',
        ),
        description: 'Rollback',
        updateOrigin: ConfigUpdateOrigin.console,
        updateType: ConfigUpdateType.rollback,
        rollbackSource: 5,
      );

      final json = data.toJson();

      expect(json['rollbackSource'], 5);
    });

    test('handles missing description', () {
      final json = {
        'versionNumber': 1,
        'updateTime': '2024-01-01T00:00:00Z',
        'updateUser': {'name': '', 'email': '', 'imageUrl': ''},
        'updateOrigin': 'CONSOLE',
        'updateType': 'INCREMENTAL_UPDATE',
      };

      final data = ConfigUpdateData.fromJson(json);
      expect(data.description, '');
    });
  });

  group('ConfigUpdateOrigin', () {
    test('parses all values', () {
      expect(
        ConfigUpdateOrigin.fromValue('REMOTE_CONFIG_UPDATE_ORIGIN_UNSPECIFIED'),
        ConfigUpdateOrigin.remoteConfigUpdateOriginUnspecified,
      );
      expect(
        ConfigUpdateOrigin.fromValue('CONSOLE'),
        ConfigUpdateOrigin.console,
      );
      expect(
        ConfigUpdateOrigin.fromValue('REST_API'),
        ConfigUpdateOrigin.restApi,
      );
      expect(
        ConfigUpdateOrigin.fromValue('ADMIN_SDK_NODE'),
        ConfigUpdateOrigin.adminSdkNode,
      );
    });

    test('defaults to unspecified for unknown values', () {
      expect(
        ConfigUpdateOrigin.fromValue('UNKNOWN'),
        ConfigUpdateOrigin.remoteConfigUpdateOriginUnspecified,
      );
    });
  });

  group('ConfigUpdateType', () {
    test('parses all values', () {
      expect(
        ConfigUpdateType.fromValue('REMOTE_CONFIG_UPDATE_TYPE_UNSPECIFIED'),
        ConfigUpdateType.remoteConfigUpdateTypeUnspecified,
      );
      expect(
        ConfigUpdateType.fromValue('INCREMENTAL_UPDATE'),
        ConfigUpdateType.incrementalUpdate,
      );
      expect(
        ConfigUpdateType.fromValue('FORCED_UPDATE'),
        ConfigUpdateType.forcedUpdate,
      );
      expect(ConfigUpdateType.fromValue('ROLLBACK'), ConfigUpdateType.rollback);
    });

    test('defaults to unspecified for unknown values', () {
      expect(
        ConfigUpdateType.fromValue('UNKNOWN'),
        ConfigUpdateType.remoteConfigUpdateTypeUnspecified,
      );
    });
  });

  group('ConfigUser', () {
    test('parses from JSON', () {
      final user = ConfigUser.fromJson({
        'name': 'John Doe',
        'email': 'john@example.com',
        'imageUrl': 'https://example.com/photo.png',
      });

      expect(user.name, 'John Doe');
      expect(user.email, 'john@example.com');
      expect(user.imageUrl, 'https://example.com/photo.png');
    });

    test('handles missing fields with defaults', () {
      final user = ConfigUser.fromJson(<String, dynamic>{});

      expect(user.name, '');
      expect(user.email, '');
      expect(user.imageUrl, '');
    });

    test('converts to JSON', () {
      const user = ConfigUser(
        name: 'Jane',
        email: 'jane@test.com',
        imageUrl: 'https://test.com/img.png',
      );

      final json = user.toJson();

      expect(json['name'], 'Jane');
      expect(json['email'], 'jane@test.com');
      expect(json['imageUrl'], 'https://test.com/img.png');
    });
  });
}
