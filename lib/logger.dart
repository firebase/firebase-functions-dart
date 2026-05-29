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

/// Structured logger for Cloud Logging.
///
/// ## Usage
///
/// ```dart
/// import 'package:firebase_functions/logger.dart' as logger;
///
/// logger.info('Request received');
/// logger.warning('Slow query', payload: {'durationMs': 1200, 'query': 'SELECT ...'});
/// logger.error('Failed to process request');
/// ```
///
/// ## Structured Logging
///
/// Pass a [Map<String, Object?>] using the named `payload:` argument to include
/// structured data in the Cloud Logging `jsonPayload`:
///
/// ```dart
/// logger.info('User signed in', payload: {
///   'userId': user.id,
///   'provider': 'google',
/// });
/// ```
library;

export 'src/logger/logger.dart';
