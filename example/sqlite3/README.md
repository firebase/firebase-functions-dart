# Native Dependencies (sqlite3) Example

Demonstrates a Firebase Functions for Dart project that depends on a package
with a **native build hook** — `sqlite3`, which compiles a C library as part of
the build.

## Why this example exists

Deploying a Dart functions project normally cross-compiles it with
`dart compile exe`, which refuses to run build hooks:

```
'dart compile' does not support build hooks, use 'dart build' instead.
Packages with build hooks: sqlite3.
```

This happens even if the package is only a transitive dependency and your own
code never imports it.

Declaring an SDK constraint of `^3.13.0` opts the project into `dart build cli`,
which runs build hooks while cross-compiling for Cloud Run:

```yaml
environment:
  sdk: ^3.13.0
```

Dart 3.13 is the release where `dart build cli` gained `--target-os` and
`--target-arch`. Projects below that constraint keep using `dart compile exe`.
Any project declaring `^3.13.0` takes the bundle path, whether or not it has
native dependencies, and needs firebase-tools 15.28.1 or later to deploy.

See [Native Dependencies](../../doc/config.md#native-dependencies-build-hooks)
for the full explanation.

## The function

`sqliteDemo` opens an in-memory database, writes a few rows, and returns the
row count alongside the linked SQLite version — proving the native library was
built and loaded successfully at runtime:

```
sqlite3 3.53.4, items: 3
```

## Running locally

Unlike the other examples, this one is not part of the repository's pub
workspace — its `^3.13.0` constraint would otherwise force every contributor
onto Dart 3.13. Resolve it on its own first:

```bash
dart pub get
```

Then:

```bash
FIREBASE_PROJECT=demo-test PORT=8080 dart run bin/server.dart
```

Then, in another terminal:

```bash
curl http://localhost:8080/sqlitedemo
```

Note the lowercase path: function names are lowercased to form valid Cloud Run
service IDs, so `sqliteDemo` is served at `/sqlitedemo`.

## Deploying

```bash
firebase deploy --only functions --project YOUR_PROJECT
```

Deploying requires Dart 3.13.0 or later installed locally, since that is the
first release in which `dart build cli` can cross-compile.
