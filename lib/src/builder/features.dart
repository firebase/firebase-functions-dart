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

/// Language-version-gated build features, read from the SDK constraint a
/// project declares rather than the installed SDK.
class DartVersionFeatures {
  /// Features for a project declaring language version [major].[minor].
  const DartVersionFeatures(int major, int minor)
    : _major = major,
      _minor = minor;

  /// Features for an undeterminable language version; falls back to pre-3.13.
  const DartVersionFeatures.unknown() : _major = null, _minor = null;

  final int? _major;
  final int? _minor;

  /// Whether `dart build cli` can build this project, which as of Dart 3.13
  /// cross-compiles and runs native build hooks that `dart compile exe` cannot.
  bool get isNativeAssetsAvailable => _atLeast(3, 13);

  bool _atLeast(int major, int minor) {
    final actualMajor = _major;
    final actualMinor = _minor;
    if (actualMajor == null || actualMinor == null) return false;
    return actualMajor > major ||
        (actualMajor == major && actualMinor >= minor);
  }
}
