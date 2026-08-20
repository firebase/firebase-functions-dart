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

/// Payload types for Billing alerts.
library;

/// Payload for billing plan update alerts.
class PlanUpdatePayload {
  const PlanUpdatePayload({
    required this.billingPlan,
    required this.principalEmail,
    required this.notificationType,
  });

  factory PlanUpdatePayload.fromJson(Map<String, dynamic> json) =>
      PlanUpdatePayload(
        billingPlan: json['billingPlan'] as String,
        principalEmail: json['principalEmail'] as String,
        notificationType: json['notificationType'] as String,
      );

  /// A Firebase billing plan.
  final String billingPlan;

  /// The email address of the person that triggered billing plan change.
  final String principalEmail;

  /// The type of the notification, e.g. upgrade, downgrade.
  final String notificationType;

  Map<String, dynamic> toJson() => {
    '@type':
        'type.googleapis.com/google.events.firebase.firebasealerts.v1.BillingPlanUpdatePayload',
    'billingPlan': billingPlan,
    'principalEmail': principalEmail,
    'notificationType': notificationType,
  };
}

/// Payload for automated billing plan update alerts.
class PlanAutomatedUpdatePayload {
  const PlanAutomatedUpdatePayload({
    required this.billingPlan,
    required this.notificationType,
  });

  factory PlanAutomatedUpdatePayload.fromJson(Map<String, dynamic> json) =>
      PlanAutomatedUpdatePayload(
        billingPlan: json['billingPlan'] as String,
        notificationType: json['notificationType'] as String,
      );

  /// A Firebase billing plan.
  final String billingPlan;

  /// The type of the notification, e.g. upgrade, downgrade.
  final String notificationType;

  Map<String, dynamic> toJson() => {
    '@type':
        'type.googleapis.com/google.events.firebase.firebasealerts.v1.BillingPlanAutomatedUpdatePayload',
    'billingPlan': billingPlan,
    'notificationType': notificationType,
  };
}
