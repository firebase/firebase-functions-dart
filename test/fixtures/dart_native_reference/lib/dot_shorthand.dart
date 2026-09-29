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

// ignore_for_file: experimental_member_use

// Dot shorthand options. Ignores below work around a Dart 3.13 analyzer bug.

import 'package:firebase_functions/firebase_functions.dart';

final shorthandMinInstances = defineInt(
  'SHORTHAND_MIN_INSTANCES',
  const .new(defaultValue: 1),
);

const HttpsOptions shorthandVariableOptions = .new(
  invoker: .public(),
  cpu: .gcfGen1(),
);

void registerDotShorthandFunctions(Firebase firebase) {
  setGlobalOptions(const .new(concurrency: .new(7)));

  firebase.https.onRequest(
    name: 'shorthandInline',
    (request) async => Response.ok('ok'),
    // ignore: non_const_argument_for_const_parameter
    options: const .new(invoker: .private(), memory: .new(.gb1)),
  );

  firebase.https.onRequest(
    name: 'shorthandVariable',
    (request) async => Response.ok('ok'),
    options: shorthandVariableOptions,
  );

  // The type is required for `.new` to resolve.
  // ignore: omit_local_variable_types
  const HttpsOptions localOptions = .new(timeoutSeconds: .new(30));
  firebase.https.onRequest(
    name: 'shorthandLocal',
    (request) async => Response.ok('ok'),
    options: localOptions,
  );

  firebase.scheduler.onSchedule(
    schedule: '0 0 * * *',
    (event) async {},
    // ignore: non_const_argument_for_const_parameter
    options: const .new(
      timeZone: .new('America/New_York'),
      retryConfig: .new(retryCount: .new(3), maxRetrySeconds: .new(60)),
    ),
  );

  firebase.tasks.onTaskDispatched(
    name: 'shorthandTasks',
    (request) async {},
    // ignore: non_const_argument_for_const_parameter
    options: const .new(
      retryConfig: .new(maxAttempts: .new(5)),
      rateLimits: .new(maxConcurrentDispatches: .new(10)),
    ),
  );
}
