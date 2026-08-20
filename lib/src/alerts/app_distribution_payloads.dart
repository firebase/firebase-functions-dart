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

/// Payload types for App Distribution alerts.
library;

/// Payload for new tester iOS device alerts.
class NewTesterDevicePayload {
  const NewTesterDevicePayload({
    required this.testerName,
    required this.testerEmail,
    required this.testerDeviceModelName,
    required this.testerDeviceIdentifier,
  });

  factory NewTesterDevicePayload.fromJson(Map<String, dynamic> json) =>
      NewTesterDevicePayload(
        testerName: json['testerName'] as String,
        testerEmail: json['testerEmail'] as String,
        testerDeviceModelName: json['testerDeviceModelName'] as String,
        testerDeviceIdentifier: json['testerDeviceIdentifier'] as String,
      );

  /// Name of the tester.
  final String testerName;

  /// Email of the tester.
  final String testerEmail;

  /// The device model name.
  final String testerDeviceModelName;

  /// The device ID.
  final String testerDeviceIdentifier;

  Map<String, dynamic> toJson() => {
    '@type':
        'type.googleapis.com/google.events.firebase.firebasealerts.v1.AppDistroNewTesterIosDevicePayload',
    'testerName': testerName,
    'testerEmail': testerEmail,
    'testerDeviceModelName': testerDeviceModelName,
    'testerDeviceIdentifier': testerDeviceIdentifier,
  };
}

/// Payload for in-app feedback alerts.
class InAppFeedbackPayload {
  const InAppFeedbackPayload({
    required this.feedbackReport,
    required this.feedbackConsoleUri,
    this.testerName,
    required this.testerEmail,
    required this.appVersion,
    required this.text,
    this.screenshotUri,
  });

  factory InAppFeedbackPayload.fromJson(Map<String, dynamic> json) =>
      InAppFeedbackPayload(
        feedbackReport: json['feedbackReport'] as String,
        feedbackConsoleUri: json['feedbackConsoleUri'] as String,
        testerName: json['testerName'] as String?,
        testerEmail: json['testerEmail'] as String,
        appVersion: json['appVersion'] as String,
        text: json['text'] as String,
        screenshotUri: json['screenshotUri'] as String?,
      );

  /// Resource name.
  /// Format: `projects/{project_number}/apps/{app_id}/releases/{release_id}/feedbackReports/{feedback_id}`
  final String feedbackReport;

  /// Deep link back to the Firebase console.
  final String feedbackConsoleUri;

  /// Name of the tester.
  final String? testerName;

  /// Email of the tester.
  final String testerEmail;

  /// Version consisting of `versionName` and `versionCode` for Android and
  /// `CFBundleShortVersionString` and `CFBundleVersion` for iOS.
  final String appVersion;

  /// Text entered by the tester.
  final String text;

  /// URI to download screenshot. This URI is fast expiring.
  final String? screenshotUri;

  Map<String, dynamic> toJson() => {
    '@type':
        'type.googleapis.com/google.events.firebase.firebasealerts.v1.AppDistroInAppFeedbackPayload',
    'feedbackReport': feedbackReport,
    'feedbackConsoleUri': feedbackConsoleUri,
    if (testerName != null) 'testerName': testerName,
    'testerEmail': testerEmail,
    'appVersion': appVersion,
    'text': text,
    if (screenshotUri != null) 'screenshotUri': screenshotUri,
  };
}
