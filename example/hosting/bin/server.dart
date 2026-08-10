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

void main() async {
  await runFunctions((firebase) {
    // An onRequest function used as a backend for Firebase Hosting rewrites.
    // All requests to the hosted site are forwarded to this function, which
    // handles routing based on the request path.
    //
    // firebase.json configures the rewrite:
    //   { "source": "**", "run": { "serviceId": "app", "region": "us-central1" } }
    firebase.https.onRequest(
      name: 'app',
      options: const HttpsOptions(invoker: Invoker.public()),
      (request) async {
        final path = request.requestedUri.path;
        return switch (path) {
          '/' => Response.ok('Home page'),
          '/about' => Response.ok('About page'),
          _ => Response.notFound('Not found: $path'),
        };
      },
    );
  });
}
