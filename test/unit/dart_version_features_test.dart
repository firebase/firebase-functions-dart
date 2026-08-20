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

import 'package:firebase_functions/src/builder/features.dart';
import 'package:test/test.dart';

void main() {
  group('DartVersionFeatures', () {
    test(
      'reports native assets unavailable for an unknown language version',
      () {
        expect(
          const DartVersionFeatures.unknown().isNativeAssetsAvailable,
          isFalse,
        );
      },
    );

    test('reports native assets unavailable below language version 3.13', () {
      expect(const DartVersionFeatures(3, 9).isNativeAssetsAvailable, isFalse);
      expect(const DartVersionFeatures(3, 12).isNativeAssetsAvailable, isFalse);
    });

    test('reports native assets available at language version 3.13', () {
      expect(const DartVersionFeatures(3, 13).isNativeAssetsAvailable, isTrue);
    });

    test('reports native assets available above language version 3.13', () {
      expect(const DartVersionFeatures(3, 14).isNativeAssetsAvailable, isTrue);
      expect(const DartVersionFeatures(4, 0).isNativeAssetsAvailable, isTrue);
    });

    test('compares minor versions numerically, not lexically', () {
      // Guards against a string comparison, where "3.9" would sort above
      // "3.13" and wrongly report native assets support.
      expect(const DartVersionFeatures(3, 9).isNativeAssetsAvailable, isFalse);
      expect(const DartVersionFeatures(3, 130).isNativeAssetsAvailable, isTrue);
    });

    test('does not treat a lower major version as supported', () {
      expect(const DartVersionFeatures(2, 19).isNativeAssetsAvailable, isFalse);
    });
  });
}
