# Flutter + firebase_functions workspace conflict (issue #236)

Reproduces [#236](https://github.com/firebase/firebase-functions-dart/issues/236):
a [pub workspace](https://dart.dev/tools/pub/workspaces) that mixes a Flutter
app with `firebase_functions` (e.g. to share models between a Flutter client
and its Dart Cloud Functions backend, as in the
[Dart Cloud Functions codelab](https://codelabs.developers.google.com/deploy-dart-on-firebase-functions))
fails to resolve on Flutter stable.

## Why

- `flutter_app` depends on `flutter` from the SDK, which pins `meta` to
  whatever exact version ships with the installed Flutter release.
- `functions` depends on `firebase_functions`, which transitively requires
  `google_cloud_shelf` and `google_cloud_logging` — both of which require
  `meta: ^1.18.2`.
- A pub workspace resolves a single `pubspec.lock` shared across all members,
  so both constraints must be satisfiable at once. Flutter stable currently
  bundles `meta 1.18.0`, so resolution fails.

This is not fixable from `firebase_functions`' own `pubspec.yaml` — the tight
`meta` lower bound lives in `google_cloud_shelf`/`google_cloud_logging`
(part of [googleapis/google-cloud-dart](https://github.com/googleapis/google-cloud-dart)).

## Reproducing

This directory is intentionally **not** part of the root repo's pub
workspace, and is excluded from CI's plain-Dart analyze sweep (see
`.github/workflows/test.yml`), since exercising it requires the Flutter SDK.
To see the failure locally:

```bash
cd example/flutter_test
flutter pub get
```

Expected output:

```
Resolving dependencies...
Note: meta is pinned to version 1.18.0 by flutter from the flutter SDK.
See https://dart.dev/go/sdk-version-pinning for details.

Because functions depends on firebase_functions ^0.7.0 which depends on
google_cloud_shelf ^0.6.0, google_cloud_shelf ^0.6.0 is required.
And because every version of google_cloud_shelf depends on meta ^1.18.2, meta
^1.18.2 is required.
So, because flutter_app depends on flutter from sdk which depends on meta
1.18.0, version solving failed.
Failed to update packages.
```

(Verified against Flutter 3.44.2 stable / Dart 3.12.2.)
