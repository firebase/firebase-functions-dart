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

import 'shared_options.dart' as shared;

part 'const_references_part.dart';

const constTimeout = 45;
const constServiceAccount = 'const-account@';
const constInvokers = ['a@example.com', 'b@example.com'];
const constLabels = {'team': 'platform'};
const constMergedLabels = {...constLabels, 'env': 'prod'};
const constRegion = SupportedRegion.europeWest2;
const constMemory = MemoryOption.gb2;
const constCpu = 2.0;
const constCustomMemory = MemoryOption(3000);
const constIntParam = IntParam('CONST_MEM', null);
const constParamMemory = Memory.param(constIntParam);
const constIsProd = true;
const constAccountName = 'interpolated';
const constTimeZone = 'Europe/London';
const constRetryCount = 4;
const constMaxAttempts = 6;

const constRegionOption = Region(SupportedRegion.asiaEast1);
const constMemoryOption = Memory(MemoryOption.gb4);
const constInvokerOption = Invoker.public();
const constTimeZoneOption = TimeZone('Asia/Tokyo');
const constRetryConfig = RetryConfig(retryCount: RetryCount(2));
const constTaskRetryConfig = TaskQueueRetryConfig(maxAttempts: MaxAttempts(7));

const collidingOptions = HttpsOptions(memory: Memory(MemoryOption.mb512));

class StaticOptions {
  static const https = HttpsOptions(
    region: Region(SupportedRegion.europeWest1),
  );
}

const constBuiltinParamOption = ServiceAccount.param(ParamInput.projectId);

const constParamOptions = ParamOptions<int>(
  defaultValue: 2,
  label: 'Const options',
);
final constOptionsParam = defineInt('CONST_PARAM_OPTIONS', constParamOptions);

void registerConstReferenceFunctions(Firebase firebase) {
  _registerPartFunctions(firebase);

  firebase.https.onRequest(
    name: 'constReferences',
    (request) async => Response.ok('ok'),
    options: const HttpsOptions(
      timeoutSeconds: TimeoutSeconds(constTimeout),
      serviceAccount: ServiceAccount(constServiceAccount),
      invoker: Invoker(constInvokers),
      labels: constMergedLabels,
      region: Region(constRegion),
      memory: Memory(constMemory),
      cpu: Cpu(constCpu),
    ),
  );

  const localTimeoutOption = TimeoutSeconds(90);
  firebase.https.onRequest(
    name: 'constOptionObjects',
    (request) async => Response.ok('ok'),
    options: const HttpsOptions(
      region: constRegionOption,
      memory: constMemoryOption,
      invoker: constInvokerOption,
      timeoutSeconds: localTimeoutOption,
    ),
  );

  firebase.scheduler.onSchedule(
    schedule: '0 4 * * *',
    (event) async {},
    options: const ScheduleOptions(
      timeZone: constTimeZoneOption,
      retryConfig: constRetryConfig,
    ),
  );

  firebase.tasks.onTaskDispatched(
    name: 'constOptionObjectTasks',
    (request) async {},
    options: const TaskQueueOptions(retryConfig: constTaskRetryConfig),
  );

  firebase.https.onRequest(
    name: 'constParamOption',
    (request) async => Response.ok('ok'),
    options: const HttpsOptions(memory: constParamMemory),
  );

  firebase.https.onRequest(
    name: 'constCustomMemory',
    (request) async => Response.ok('ok'),
    options: const HttpsOptions(memory: Memory(constCustomMemory)),
  );

  firebase.https.onRequest(
    name: 'constExpressions',
    (request) async => Response.ok('ok'),
    options: const HttpsOptions(
      timeoutSeconds: TimeoutSeconds(constTimeout * 2),
      serviceAccount: ServiceAccount('$constAccountName@'),
      invoker: Invoker([...constInvokers, 'c@example.com']),
      labels: {...constLabels, if (constIsProd) 'env': 'prod'},
    ),
  );

  firebase.https.onRequest(
    name: 'customMemoryInline',
    (request) async => Response.ok('ok'),
    options: const HttpsOptions(memory: Memory(MemoryOption(1536))),
  );

  firebase.https.onRequest(
    name: 'staticFieldOptions',
    (request) async => Response.ok('ok'),
    options: StaticOptions.https,
  );

  firebase.https.onRequest(
    name: 'prefixedOptions',
    (request) async => Response.ok('ok'),
    options: shared.collidingOptions,
  );

  firebase.https.onRequest(
    name: 'collidingOptions',
    (request) async => Response.ok('ok'),
    options: collidingOptions,
  );

  firebase.https.onRequest(
    name: 'builtinParamOption',
    (request) async => Response.ok('ok'),
    options: const HttpsOptions(
      serviceAccount: ServiceAccount.param(ParamInput.projectId),
    ),
  );

  firebase.https.onRequest(
    name: 'constBuiltinParamOption',
    (request) async => Response.ok('ok'),
    options: const HttpsOptions(serviceAccount: constBuiltinParamOption),
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
