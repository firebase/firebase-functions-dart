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
import 'package:firebase_functions_genkit/firebase_functions_genkit.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_google_genai/genkit_google_genai.dart';

const name = 'jokeTeller';

void main(List<String> args) {
  final gemini = googleAI();
  final ai = Genkit(plugins: [gemini]);
  final flow = ai.defineFlow(
    name: name,
    inputSchema: .string(),
    outputSchema: .string(),
    streamSchema: .string(),
    fn: (jokeType, context) async {
      final prompt = 'Tell me a $jokeType joke.';

      /// gemini.model does not have a generic type
      // ignore: inference_failure_on_function_invocation
      final stream = ai.generateStream(
        model: gemini.model('gemini-2.5-flash'),
        prompt: prompt,
      );
      await stream.forEach((chunk) => context.sendChunk(chunk.text));
      return stream.result.text;
    },
  );

  fireUp(args, (firebase) {
    firebase.https.onCallGenkit(
      name: name,
      flow: flow,
      contextProvider: (request) => {'auth': request.auth?.token?['email']},
    );
  });
}
