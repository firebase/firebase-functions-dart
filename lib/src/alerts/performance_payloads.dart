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

/// Payload types for Performance alerts.
library;

/// Payload for performance threshold alerts.
class ThresholdAlertPayload {
  const ThresholdAlertPayload({
    required this.eventName,
    required this.eventType,
    required this.metricType,
    required this.numSamples,
    required this.thresholdValue,
    required this.thresholdUnit,
    this.conditionPercentile,
    this.appVersion,
    required this.violationValue,
    required this.violationUnit,
    required this.investigateUri,
  });

  factory ThresholdAlertPayload.fromJson(Map<String, dynamic> json) {
    // Handle conditionPercentile: omit if 0 or missing
    final rawConditionPercentile = json['conditionPercentile'] as int?;
    final conditionPercentile =
        (rawConditionPercentile == null || rawConditionPercentile == 0)
        ? null
        : rawConditionPercentile;

    // Handle appVersion: omit if empty or missing
    final rawAppVersion = json['appVersion'] as String?;
    final appVersion = (rawAppVersion == null || rawAppVersion.isEmpty)
        ? null
        : rawAppVersion;

    return ThresholdAlertPayload(
      eventName: json['eventName'] as String,
      eventType: json['eventType'] as String,
      metricType: json['metricType'] as String,
      numSamples: json['numSamples'] as int,
      thresholdValue: (json['thresholdValue'] as num).toDouble(),
      thresholdUnit: json['thresholdUnit'] as String,
      conditionPercentile: conditionPercentile,
      appVersion: appVersion,
      violationValue: (json['violationValue'] as num).toDouble(),
      violationUnit: json['violationUnit'] as String,
      investigateUri: json['investigateUri'] as String,
    );
  }

  /// Name of the trace or network request this alert is for
  /// (e.g. my_custom_trace, firebase.com/api/123).
  final String eventName;

  /// The resource type this alert is for
  /// (i.e. trace, network request, screen rendering, etc.).
  final String eventType;

  /// The metric type this alert is for
  /// (i.e. success rate, response time, duration, etc.).
  final String metricType;

  /// The number of events checked for this alert condition.
  final int numSamples;

  /// The threshold value of the alert condition without units
  /// (e.g. "75", "2.1").
  final double thresholdValue;

  /// The unit for the alert threshold (e.g. "percent", "seconds").
  final String thresholdUnit;

  /// The percentile of the alert condition.
  /// Can be null if percentile is not applicable to the alert condition.
  /// Range: `[1, 100]`.
  final int? conditionPercentile;

  /// The app version this alert was triggered for.
  /// Can be null if the alert is for a network request (because the alert
  /// was checked against data from all versions of app) or a web app
  /// (where the app is versionless).
  final String? appVersion;

  /// The value that violated the alert condition (e.g. "76.5", "3").
  final double violationValue;

  /// The unit for the violation value (e.g. "percent", "seconds").
  final String violationUnit;

  /// The link to Firebase console to investigate more into this alert.
  final String investigateUri;

  Map<String, dynamic> toJson() => {
    '@type':
        'type.googleapis.com/google.events.firebase.firebasealerts.v1.PerformanceThresholdAlertPayload',
    'eventName': eventName,
    'eventType': eventType,
    'metricType': metricType,
    'numSamples': numSamples,
    'thresholdValue': thresholdValue,
    'thresholdUnit': thresholdUnit,
    if (conditionPercentile != null) 'conditionPercentile': conditionPercentile,
    if (appVersion != null) 'appVersion': appVersion,
    'violationValue': violationValue,
    'violationUnit': violationUnit,
    'investigateUri': investigateUri,
  };
}
