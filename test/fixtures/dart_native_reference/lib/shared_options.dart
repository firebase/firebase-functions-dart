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

// Options and params imported with a prefix by const_references.dart, which
// declares another `collidingOptions`, and by param_references.dart.

import 'package:firebase_functions/firebase_functions.dart';

const collidingOptions = HttpsOptions(memory: Memory(MemoryOption.gb8));

final sharedMinInstances = defineInt('SHARED_MIN_INSTANCES');
final sharedSecret = defineSecret('SHARED_SECRET');
final sharedIsLarge = defineBoolean('SHARED_IS_LARGE');

class SharedParams {
  static final memory = defineInt('STATIC_MEMORY');
}
