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

// Params referenced from another file, a static field, a local variable or
// through an import prefix must resolve to the name they were defined with.

import 'package:firebase_functions/firebase_functions.dart';
import 'package:firebase_functions/params.dart' as params;

import 'shared_options.dart' as shared;

final prefixedParam = params.defineString('PREFIXED_PARAM');

void registerParamReferenceFunctions(Firebase firebase) {
  final localParam = defineInt('LOCAL_PARAM_NAME');

  firebase.https.onRequest(
    name: 'paramReferences',
    (request) async => Response.ok('ok'),
    // ignore: non_const_argument_for_const_parameter
    options: HttpsOptions(
      minInstances: DeployOption.param(shared.sharedMinInstances),
      maxInstances: DeployOption.param(localParam),
      memory: Memory.param(shared.SharedParams.memory),
      serviceAccount: ServiceAccount.param(prefixedParam),
      secrets: [shared.sharedSecret],
    ),
  );

  firebase.https.onRequest(
    name: 'paramExpressionReference',
    (request) async => Response.ok('ok'),
    // ignore: non_const_argument_for_const_parameter
    options: HttpsOptions(
      memory: Memory.expression(shared.sharedIsLarge.thenElse(2048, 512)),
    ),
  );

  firebase.https.onRequest(
    name: 'publicBuiltinParamReference',
    (request) async => Response.ok('ok'),
    options: const HttpsOptions(
      serviceAccount: ServiceAccount.param(projectID),
    ),
  );
}
