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
import 'package:genkit/genkit.dart';

/// It's experimental as we can't semver package:meta
// ignore: experimental_member_use
import 'package:meta/meta.dart' show mustBeConst;

/// Extension on [HttpsNamespace] to provide a seamless integration with Genkit.
extension GenkitExt on HttpsNamespace {
  /// Registers a Genkit [flow] as a Firebase callable function.
  ///
  /// Automatically handles streaming and non-streaming responses based on
  /// [CallableRequest.acceptsStreaming].
  ///
  /// Use [contextProvider] to map properties from the Firebase
  /// [CallableRequest] (such as authentication tokens) into the Genkit context.
  void onCallGenkit<Output extends Object, Init>({
    // Must repeat the name
    /// It's experimental as we can't semver package:meta
    // ignore: experimental_member_use
    @mustBeConst required String name,
    required Flow<Object?, Output, Output, Init> flow,

    /// It's experimental as we can't semver package:meta
    // ignore: experimental_member_use
    @mustBeConst CallableOptions? options = const CallableOptions(),
    Map<String, dynamic> Function(CallableRequest<Object?>)? contextProvider,
  }) {
    /// This is why we restate the name in the params above
    // ignore: non_const_argument_for_const_parameter
    onCall<Output>(name: name, options: options, (request, response) async {
      if (request.acceptsStreaming) {
        final actionStream = flow.stream(
          request.data,
          context: contextProvider?.call(request),
        );
        await actionStream.forEach((chunk) => response.sendChunk(chunk));
        return CallableResult(actionStream.result);
      } else {
        final run = await flow.run(
          request.data,
          context: contextProvider?.call(request),
        );
        return CallableResult(run.result);
      }
    });
  }
}
