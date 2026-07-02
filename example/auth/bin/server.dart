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

// ignore_for_file: experimental_member_use

import 'package:firebase_functions/firebase_functions.dart';

void main(List<String> args) async {
  await runFunctions((firebase) {
    // Before user created - runs before a new user is created
    firebase.identity.beforeUserCreated(
      options: const BlockingOptions(idToken: true, accessToken: true),
      (AuthBlockingEvent event) async {
        final user = event.data;
        print('Before user created:');
        print('  UID: ${user?.uid}');
        print('  Email: ${user?.email}');
        print('  Provider: ${event.additionalUserInfo?.providerId}');

        // Example: Block users with certain email domains
        final email = user?.email;
        if (email != null && email.endsWith('@blocked.com')) {
          throw HttpResponseException.forbidden(
            message: 'Email domain not allowed',
          );
        }

        // Example: Set custom claims based on email domain
        if (email != null && email.endsWith('@admin.com')) {
          return const BeforeCreateResponse(customClaims: {'admin': true});
        }

        return null;
      },
    );

    // Before user signed in - runs before a user signs in
    firebase.identity.beforeUserSignedIn(
      options: const BlockingOptions(idToken: true),
      (AuthBlockingEvent event) async {
        final user = event.data;
        print('Before user signed in:');
        print('  UID: ${user?.uid}');
        print('  Email: ${user?.email}');
        print('  IP Address: ${event.ipAddress}');

        // Example: Add session claims for tracking
        return BeforeSignInResponse(
          sessionClaims: {
            'lastLogin': DateTime.now().toIso8601String(),
            'signInIp': event.ipAddress,
          },
        );
      },
    );

    // Before email sent - runs before password reset or sign-in emails
    firebase.identity.beforeEmailSent((AuthBlockingEvent event) async {
      print('Before email sent:');
      print('  Email Type: ${event.emailType?.value}');
      print('  IP Address: ${event.ipAddress}');

      if (event.emailType == EmailType.passwordReset) {
        // Could block suspicious requests
      }

      return null;
    });

    // Before SMS sent - runs before MFA or sign-in SMS messages
    firebase.identity.beforeSmsSent((AuthBlockingEvent event) async {
      print('Before SMS sent:');
      print('  SMS Type: ${event.smsType?.value}');
      print('  Phone: ${event.additionalUserInfo?.phoneNumber}');

      // Example: Block SMS to certain country codes
      final phone = event.additionalUserInfo?.phoneNumber;
      if (phone != null && phone.startsWith('+1900')) {
        return const BeforeSmsResponse(
          recaptchaActionOverride: RecaptchaActionOptions.block,
        );
      }

      return null;
    });
  });
}
