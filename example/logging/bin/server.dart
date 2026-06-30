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
import 'package:firebase_functions/logger.dart' as logger;

void main(List<String> args) async {
  await runFunctions((firebase) {
    // #region call
    firebase.https.onCall(name: 'hello', (request, response) async {
      // #region debug
      logger.debug('hello');
      // #endregion debug

      // Logging messages can be supplemented with addition data that can be
      // queried using the Google Cloud Log's Explorer.
      // #region info
      logger.info('request information', {
        'authenticated': request.auth != null,
      });
      // #endregion info

      // Logging messages can include information about the stack that resulted
      // in the logging message.
      // #region error
      String name;
      try {
        name = await _lookupName();
      } catch (e, s) {
        name = 'my friend';
        logger.error('database error', {'error': e.toString()}, s);
      }
      // #endregion error

      return CallableResult({'message': 'Hello, $name!'});
    });
    // #endregion call
  });
}

Future<String> _lookupName() async {
  throw StateError('Database connection was unexpectedly closed.');
}
