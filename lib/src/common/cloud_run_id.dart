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

/// Converts a function name to a valid Cloud Run service ID.
///
/// Cloud Run service IDs must:
/// - Only contain lowercase letters, digits, and hyphens
/// - Begin with a letter
/// - Not end with a hyphen
/// - Be less than 50 characters
///
/// Names are lowercased as-is (no camelCase splitting), matching what the
/// Cloud Functions v2 API does internally for Node.js and Python functions:
/// - `helloWorld` → `helloworld`
/// - `getAuthInfo` → `getauthinfo`
///
/// Underscores and other invalid characters become hyphens:
/// - `onDocumentCreated_users_userId` → `ondocumentcreated-users-userid`
///
/// This function is used by both the build-time manifest generator and the
/// runtime function registration to ensure consistent naming.
String toCloudRunId(String name) {
  // Step 1: Lowercase
  var id = name.toLowerCase();

  // Step 2: Replace non-alphanumeric chars with hyphens
  id = id.replaceAll(RegExp(r'[^a-z0-9]'), '-');

  // Step 3: Collapse consecutive hyphens
  id = id.replaceAll(RegExp(r'-{2,}'), '-');

  // Step 4: Remove leading hyphens/digits (must start with a letter)
  id = id.replaceAll(RegExp(r'^[^a-z]+'), '');

  // Step 5: Remove trailing hyphens
  id = id.replaceAll(RegExp(r'-+$'), '');

  // Step 6: Handle 50-char limit
  if (id.length >= 50) {
    // Use a deterministic hash suffix to avoid collisions
    final hash = _simpleHash(name);
    final suffix = hash.substring(0, 6);
    // Reserve space for: truncated part + '-' + 6-char hash = max 49
    var prefix = id.substring(0, 42);
    // Don't end the prefix on a hyphen
    prefix = prefix.replaceAll(RegExp(r'-+$'), '');
    id = '$prefix-$suffix';
  }

  return id;
}

/// Simple deterministic hash that returns a lowercase alphanumeric string.
String _simpleHash(String input) {
  // DJB2 hash — deterministic across all Dart runtimes
  var hash = 5381;
  for (var i = 0; i < input.length; i++) {
    hash = ((hash << 5) + hash) + input.codeUnitAt(i);
    hash &= 0x7FFFFFFF; // Keep it positive 31-bit
  }
  // Convert to base-36 (lowercase alphanumeric)
  return hash.toRadixString(36).padLeft(6, '0');
}
