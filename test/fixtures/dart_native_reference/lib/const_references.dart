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

// Options referencing `const` variables must match their literal forms.

import 'package:firebase_functions/firebase_functions.dart';

const constTimeout = 45;
const constServiceAccount = 'const-account@';
const constInvokers = ['a@example.com', 'b@example.com'];
const constLabels = {'team': 'platform'};
const constRegion = SupportedRegion.europeWest2;
const constMemory = MemoryOption.gb2;
const constCpu = 2.0;
const constCustomMemory = MemoryOption(3000);
const constTimeZone = 'Europe/London';
const constRetryCount = 4;
const constMaxAttempts = 6;

void registerConstReferenceFunctions(Firebase firebase) {
  firebase.https.onRequest(
    name: 'constReferences',
    (request) async => Response.ok('ok'),
    options: const HttpsOptions(
      timeoutSeconds: TimeoutSeconds(constTimeout),
      serviceAccount: ServiceAccount(constServiceAccount),
      invoker: Invoker(constInvokers),
      labels: constLabels,
      region: Region(constRegion),
      memory: Memory(constMemory),
      cpu: Cpu(constCpu),
    ),
  );

  firebase.https.onRequest(
    name: 'constCustomMemory',
    (request) async => Response.ok('ok'),
    options: const HttpsOptions(memory: Memory(constCustomMemory)),
  );

  firebase.scheduler.onSchedule(
    schedule: '0 3 * * *',
    (event) async {},
    options: const ScheduleOptions(
      timeZone: TimeZone(constTimeZone),
      retryConfig: RetryConfig(retryCount: RetryCount(constRetryCount)),
    ),
  );

  firebase.tasks.onTaskDispatched(
    name: 'constReferenceTasks',
    (request) async {},
    options: const TaskQueueOptions(
      retryConfig: TaskQueueRetryConfig(
        maxAttempts: MaxAttempts(constMaxAttempts),
      ),
    ),
  );
}
