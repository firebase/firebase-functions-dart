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

/// Payload types for Crashlytics alerts.
library;

/// Generic Crashlytics issue interface.
class Issue {
  const Issue({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.appVersion,
  });

  factory Issue.fromJson(Map<String, dynamic> json) => Issue(
    id: json['id'] as String,
    title: json['title'] as String,
    subtitle: json['subtitle'] as String,
    appVersion: json['appVersion'] as String,
  );

  /// The ID of the Crashlytics issue.
  final String id;

  /// The title of the Crashlytics issue.
  final String title;

  /// The subtitle of the Crashlytics issue.
  final String subtitle;

  /// The application version of the Crashlytics issue.
  final String appVersion;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'appVersion': appVersion,
  };
}

/// Payload for a new fatal issue alert.
class NewFatalIssuePayload {
  const NewFatalIssuePayload({required this.issue});

  factory NewFatalIssuePayload.fromJson(Map<String, dynamic> json) =>
      NewFatalIssuePayload(
        issue: Issue.fromJson(json['issue'] as Map<String, dynamic>),
      );

  /// Basic information of the Crashlytics issue.
  final Issue issue;

  Map<String, dynamic> toJson() => {
    '@type':
        'type.googleapis.com/google.events.firebase.firebasealerts.v1.CrashlyticsNewFatalIssuePayload',
    'issue': issue.toJson(),
  };
}

/// Payload for a new non-fatal issue alert.
class NewNonfatalIssuePayload {
  const NewNonfatalIssuePayload({required this.issue});

  factory NewNonfatalIssuePayload.fromJson(Map<String, dynamic> json) =>
      NewNonfatalIssuePayload(
        issue: Issue.fromJson(json['issue'] as Map<String, dynamic>),
      );

  /// Basic information of the Crashlytics issue.
  final Issue issue;

  Map<String, dynamic> toJson() => {
    '@type':
        'type.googleapis.com/google.events.firebase.firebasealerts.v1.CrashlyticsNewNonfatalIssuePayload',
    'issue': issue.toJson(),
  };
}

/// Payload for a regression alert.
class RegressionAlertPayload {
  const RegressionAlertPayload({
    required this.type,
    required this.issue,
    required this.resolveTime,
  });

  factory RegressionAlertPayload.fromJson(Map<String, dynamic> json) =>
      RegressionAlertPayload(
        type: json['type'] as String,
        issue: Issue.fromJson(json['issue'] as Map<String, dynamic>),
        resolveTime: DateTime.parse(json['resolveTime'] as String),
      );

  /// The type of the Crashlytics issue, e.g. new fatal, new nonfatal, ANR.
  final String type;

  /// Basic information of the Crashlytics issue.
  final Issue issue;

  /// The time that the Crashlytics issue was most recently resolved
  /// before it began to reoccur.
  final DateTime resolveTime;

  Map<String, dynamic> toJson() => {
    '@type':
        'type.googleapis.com/google.events.firebase.firebasealerts.v1.CrashlyticsRegressionAlertPayload',
    'type': type,
    'issue': issue.toJson(),
    'resolveTime': resolveTime.toIso8601String(),
  };
}

/// Generic Crashlytics trending issue interface.
class TrendingIssueDetails {
  const TrendingIssueDetails({
    required this.type,
    required this.issue,
    required this.eventCount,
    required this.userCount,
  });

  factory TrendingIssueDetails.fromJson(Map<String, dynamic> json) =>
      TrendingIssueDetails(
        type: json['type'] as String,
        issue: Issue.fromJson(json['issue'] as Map<String, dynamic>),
        eventCount: json['eventCount'] as int,
        userCount: json['userCount'] as int,
      );

  /// The type of the Crashlytics issue, e.g. new fatal, new nonfatal, ANR.
  final String type;

  /// Basic information of the Crashlytics issue.
  final Issue issue;

  /// The number of crashes that occurred with the issue.
  final int eventCount;

  /// The number of distinct users that were affected by the issue.
  final int userCount;

  Map<String, dynamic> toJson() => {
    'type': type,
    'issue': issue.toJson(),
    'eventCount': eventCount,
    'userCount': userCount,
  };
}

/// Payload for a stability digest alert.
class StabilityDigestPayload {
  const StabilityDigestPayload({
    required this.digestDate,
    required this.trendingIssues,
  });

  factory StabilityDigestPayload.fromJson(Map<String, dynamic> json) =>
      StabilityDigestPayload(
        digestDate: DateTime.parse(json['digestDate'] as String),
        trendingIssues: (json['trendingIssues'] as List)
            .map(
              (e) => TrendingIssueDetails.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      );

  /// The date that the digest was created.
  /// Issues in the digest should have the same date as the digest date.
  final DateTime digestDate;

  /// A stability digest containing several trending Crashlytics issues.
  final List<TrendingIssueDetails> trendingIssues;

  Map<String, dynamic> toJson() => {
    '@type':
        'type.googleapis.com/google.events.firebase.firebasealerts.v1.CrashlyticsStabilityDigestPayload',
    'digestDate': digestDate.toIso8601String(),
    'trendingIssues': trendingIssues.map((e) => e.toJson()).toList(),
  };
}

/// Payload for a velocity alert.
class VelocityAlertPayload {
  const VelocityAlertPayload({
    required this.issue,
    required this.createTime,
    required this.crashCount,
    required this.crashPercentage,
    required this.firstVersion,
  });

  factory VelocityAlertPayload.fromJson(Map<String, dynamic> json) =>
      VelocityAlertPayload(
        issue: Issue.fromJson(json['issue'] as Map<String, dynamic>),
        createTime: DateTime.parse(json['createTime'] as String),
        crashCount: json['crashCount'] as int,
        crashPercentage: (json['crashPercentage'] as num).toDouble(),
        firstVersion: json['firstVersion'] as String,
      );

  /// Basic information of the Crashlytics issue.
  final Issue issue;

  /// The time that the Crashlytics issue was created.
  final DateTime createTime;

  /// The number of user sessions for the given app version that had this
  /// specific crash issue in the time period used to trigger the velocity alert.
  final int crashCount;

  /// The percentage of user sessions for the given app version that had this
  /// specific crash issue in the time period used to trigger the velocity alert.
  final double crashPercentage;

  /// The first app version where this issue was seen, and not necessarily the
  /// version that has triggered the alert.
  final String firstVersion;

  Map<String, dynamic> toJson() => {
    '@type':
        'type.googleapis.com/google.events.firebase.firebasealerts.v1.CrashlyticsVelocityAlertPayload',
    'issue': issue.toJson(),
    'createTime': createTime.toIso8601String(),
    'crashCount': crashCount,
    'crashPercentage': crashPercentage,
    'firstVersion': firstVersion,
  };
}

/// Payload for a new Application Not Responding issue alert.
class NewAnrIssuePayload {
  const NewAnrIssuePayload({required this.issue});

  factory NewAnrIssuePayload.fromJson(Map<String, dynamic> json) =>
      NewAnrIssuePayload(
        issue: Issue.fromJson(json['issue'] as Map<String, dynamic>),
      );

  /// Basic information of the Crashlytics issue.
  final Issue issue;

  Map<String, dynamic> toJson() => {
    '@type':
        'type.googleapis.com/google.events.firebase.firebasealerts.v1.CrashlyticsNewAnrIssuePayload',
    'issue': issue.toJson(),
  };
}
