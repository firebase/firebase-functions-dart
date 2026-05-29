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

import 'package:firebase_functions/firebase_functions.dart';

// Define parameters - these are read from environment variables at runtime
// and can be configured at deploy time via .env files or CLI prompts.
final welcomeMessage = defineString(
  'WELCOME_MESSAGE',
  const ParamOptions(
    defaultValue: 'Hello from Dart Functions!',
    label: 'Welcome Message',
    description: 'The greeting message returned by the helloWorld function',
  ),
);

final minInstances = defineInt(
  'MIN_INSTANCES',
  const ParamOptions(
    defaultValue: 0,
    label: 'Minimum Instances',
    description: 'Minimum number of instances to keep warm',
  ),
);

final isProduction = defineBoolean(
  'IS_PRODUCTION',
  const ParamOptions(
    defaultValue: false,
    description: 'Whether this is a production deployment',
  ),
);

void main(List<String> args) async {
  await runFunctions((firebase) {
    // Basic callable function - untyped data
    firebase.https.onCall(name: 'greet', (request, response) async {
      final data = request.data as Map<String, dynamic>?;
      final name = data?['name'] ?? 'World';
      return CallableResult({'message': 'Hello, $name!'});
    });

    // Callable function with typed data using fromJson
    firebase.https.onCallWithData<GreetRequest, GreetResponse>(
      name: 'greetTyped',
      fromJson: GreetRequest.fromJson,
      (request, response) async {
        return GreetResponse(message: 'Hello, ${request.data.name}!');
      },
    );

    // Callable function demonstrating error handling
    firebase.https.onCall(name: 'divide', (request, response) async {
      final data = request.data as Map<String, dynamic>?;
      final a = (data?['a'] as num?)?.toDouble();
      final b = (data?['b'] as num?)?.toDouble();

      if (a == null || b == null) {
        throw InvalidArgumentError('Both "a" and "b" are required');
      }

      if (b == 0) {
        throw FailedPreconditionError('Cannot divide by zero');
      }

      return CallableResult({'result': a / b});
    });

    // Callable function demonstrating auth data extraction
    firebase.https.onCall(name: 'getAuthInfo', (request, response) async {
      final auth = request.auth;

      if (auth == null) {
        return CallableResult({
          'authenticated': false,
          'message': 'No authentication provided',
        });
      }

      return CallableResult({
        'authenticated': true,
        'uid': auth.uid,
        'token': auth.token,
      });
    });

    // Callable function with streaming support
    firebase.https.onCall(
      name: 'countdown',
      options: const CallableOptions(
        heartBeatIntervalSeconds: HeartBeatIntervalSeconds(5),
      ),
      (request, response) async {
        final data = request.data as Map<String, dynamic>?;
        final start = (data?['start'] as num?)?.toInt() ?? 10;

        if (request.acceptsStreaming) {
          for (var i = start; i >= 0; i--) {
            await response.sendChunk({'count': i});
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }

        return CallableResult({'message': 'Countdown complete!'});
      },
    );

    // HTTPS onRequest example - using parameterized configuration
    firebase.https.onRequest(
      name: 'helloWorld',
      // ignore: non_const_argument_for_const_parameter
      options: HttpsOptions(minInstances: DeployOption.param(minInstances)),
      (request) async {
        return Response.ok(welcomeMessage.value());
      },
    );

    // Conditional configuration based on boolean parameter
    firebase.https.onRequest(
      name: 'configuredEndpoint',
      // ignore: non_const_argument_for_const_parameter
      options: HttpsOptions(
        memory: Memory.expression(isProduction.thenElse(2048, 512)),
      ),
      (request) async {
        final env = isProduction.value() ? 'production' : 'development';
        return Response.ok('Running in $env mode');
      },
    );
  });
}

/// Request data for the greetTyped callable function.
class GreetRequest {
  GreetRequest({required this.name});

  factory GreetRequest.fromJson(Map<String, dynamic> json) {
    return GreetRequest(name: json['name'] as String? ?? 'World');
  }

  final String name;

  Map<String, dynamic> toJson() => {'name': name};
}

/// Response data for the greetTyped callable function.
class GreetResponse {
  GreetResponse({required this.message});

  final String message;

  Map<String, dynamic> toJson() => {'message': message};
}
