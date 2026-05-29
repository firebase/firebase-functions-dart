# Dart Firebase SDK for Cloud Functions

<!--
Keep this content in sync with the Node and Python READMEs:
  - https://github.com/firebase/firebase-functions
  - https://github.com/firebase/firebase-functions-python
-->

[![Tests](https://github.com/firebase/firebase-functions-dart/actions/workflows/test.yml/badge.svg)](https://github.com/firebase/firebase-functions-dart/actions/workflows/test.yml)
[![pub package](https://img.shields.io/pub/v/firebase_functions.svg)](https://pub.dev/packages/firebase_functions)

The `firebase_functions` package provides an SDK for defining Cloud Functions for Firebase in Dart.

Cloud Functions is a hosted, private, and scalable environment where you can run code. The Firebase SDK for Cloud Functions integrates the Firebase platform by letting you write code that responds to events and invokes functionality exposed by other Firebase features.

## Learn more

Learn more about the Firebase SDK for Cloud Functions in the [Firebase documentation](https://firebase.google.com/docs/functions/) or [check out our samples](example/).

Here are some resources to get help:

- [Start with the quickstart](https://firebase.google.com/docs/functions/start-dart)
- [Go through the guides](https://firebase.google.com/docs/functions/)
- [Read the full API reference](https://pub.dev/documentation/firebase_functions/latest/)
- [Browse some examples](example/)
- [Learn how to configure your application](doc/config.md) <!-- Remove when integrated into Firebase docs -->
- [Codelabs](https://codelabs.developers.google.com/deploy-dart-on-firebase-functions)


If the official documentation doesn't help, try asking through our [official support channels](https://firebase.google.com/support/).

## Usage

```dart
import 'package:firebase_functions/firebase_functions.dart';

void main(List<String> args) {
  runFunctions((firebase) {
    firebase.https.onRequest(
      name: 'hello',
      (request) async {
        return Response.ok('Hello from Dart!');
      },
    );
  });
}
```

## Status: Experimental

This package provides a Dart implementation of Firebase Cloud Functions. Only HTTPS triggers are currently supported in production. Other trigger types are experimental and have [varying levels of support](doc/triggers.md).

