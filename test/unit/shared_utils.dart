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

import 'package:firebase_functions/src/firebase.dart';
import 'package:firebase_functions/src/server.dart';
import 'package:shelf/shelf.dart';

/// Finds a registered function declaration by name.
FirebaseFunctionDeclaration findFunction(Firebase firebase, String name) {
  return firebase.functions.firstWhere((f) => f.name == name.toLowerCase());
}

/// Creates a handler for testing error handling via full middleware pipeline.
Handler findHandler(Firebase firebase, String name) {
  final testHandler = createTestHandler(firebase);
  return (request) {
    return testHandler(
      Request(
        request.method,
        Uri.parse('http://localhost/${name.toLowerCase()}'),
        headers: request.headers,
        body: request.read(),
        context: request.context,
      ),
    );
  };
}
