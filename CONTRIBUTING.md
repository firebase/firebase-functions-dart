# Contributing to Firebase Functions for Dart

Thank you for contributing to Firebase Functions for Dart! This guide will help you get set up and familiar with the project conventions.

## Contributor License Agreement

Contributions to this project must be accompanied by a Contributor License Agreement (CLA). You (or your employer) retain the copyright to your contribution; the CLA gives us permission to use and redistribute your contributions as part of the project.

Visit <https://cla.developers.google.com/> to see your current agreements on file or to sign a new one. You generally only need to submit a CLA once, so if you have already submitted one you probably don't need to do it again.

## Code Reviews

All submissions, including submissions by project members, require review. We use GitHub pull requests for this purpose. Consult [GitHub Help](https://help.github.com/articles/about-pull-requests/) for more information on pull requests.

## Getting Started

### Prerequisites

- **Dart SDK** >= 3.9.0
- **Node.js** v22 (required for snapshot tests and the Firebase Emulator)
- **Java 21+** (required for the Firestore emulator)

### Setup

1. Fork and clone the repository.

2. Install Dart dependencies:

   ```bash
   cd firebase-functions-dart
   dart pub upgrade
   ```

3. Verify your setup by running the analyzer and tests:

   ```bash
   dart analyze --fatal-infos
   dart test --exclude-tags=snapshot,integration
   ```

## Development Workflow

### Project Structure

```
firebase-functions-dart/
├── lib/
│   ├── firebase_functions.dart   # Public API barrel file
│   ├── builder.dart              # Build-time code generator (AST visitor)
│   ├── params.dart               # Parameter definitions
│   └── src/                      # Private implementation
│       ├── firebase.dart         # Firebase class & function registration
│       ├── server.dart           # Shelf HTTP server & routing
│       ├── builder/              # YAML manifest generation
│       ├── common/               # Shared types (CloudEvent, options, etc.)
│       ├── https/                # HTTPS triggers
│       ├── pubsub/               # Pub/Sub triggers
│       ├── firestore/            # Firestore triggers
│       ├── database/             # Realtime Database triggers
│       ├── alerts/               # Firebase Alerts triggers
│       ├── identity/             # Identity Platform (auth blocking)
│       └── scheduler/            # Scheduled functions
├── test/
│   ├── unit/                     # Unit tests
│   ├── snapshots/                # Manifest compatibility tests (Dart vs Node.js)
│   └── e2e/                      # End-to-end tests with Firebase Emulator
└── example/                      # Example projects used by tests
```

### Running Tests

```bash
# Unit tests only (fast, no external dependencies)
dart test --exclude-tags=snapshot,integration

# Snapshot tests (compares generated manifests against Node.js reference)
dart test test/snapshots/ -t snapshot

# Build the manifest for a test fixture
cd test/fixtures/dart_reference
dart run build_runner build --delete-conflicting-outputs
cd ../../..

# End-to-end tests (requires Firebase Emulator)
dart test test/e2e/e2e_test.dart
```

### Code Formatting and Analysis

```bash
# Check formatting (CI will reject unformatted code)
dart format --output=none --set-exit-if-changed .

# Apply formatting
dart format .

# Run the analyzer (must pass with zero issues)
dart analyze --fatal-infos
```

### License Headers

All source files must include a license header. The project uses [addlicense](https://github.com/google/addlicense) to manage this automatically.

**Install addlicense:**

Download the binary for your platform from the [v1.2.0 release](https://github.com/google/addlicense/releases/tag/v1.2.0) and place it on your `PATH`. For example, on macOS ARM64:

```bash
curl -sL https://github.com/google/addlicense/releases/download/v1.2.0/addlicense_v1.2.0_macOS_arm64.tar.gz | tar xz
sudo mv addlicense /usr/local/bin/
```

**Add headers to new files:**

```bash
addlicense -f header_template.txt \
  --ignore "**/*.yml" --ignore "**/*.yaml" --ignore "**/*.xml" \
  --ignore "**/*.g.dart" --ignore "**/*.sh" --ignore "**/*.html" \
  --ignore "**/*.js" --ignore "**/*.ts" --ignore "**/*.txt" \
  --ignore "**/.dart_tool/**" \
  --ignore "**/test/fixtures/nodejs_reference/**" \
  --ignore "**/test/fixtures/with_options_nodejs/**" \
  .
```

**Check headers (dry run, same as CI):**

```bash
addlicense -f header_template.txt --check \
  --ignore "**/*.yml" --ignore "**/*.yaml" --ignore "**/*.xml" \
  --ignore "**/*.g.dart" --ignore "**/*.sh" --ignore "**/*.html" \
  --ignore "**/*.js" --ignore "**/*.ts" --ignore "**/*.txt" \
  --ignore "**/.dart_tool/**" \
  --ignore "**/test/fixtures/nodejs_reference/**" \
  --ignore "**/test/fixtures/with_options_nodejs/**" \
  .
```

CI will fail if any source file is missing its license header.

### Local Validation

You can run the full CI check suite locally before pushing:

```bash
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test --exclude-tags=snapshot,integration
```

## Code Standards

### Style

The project uses strict analysis settings (`strict-casts`, `strict-inference`, `strict-raw-types`) and 49 linter rules defined in `analysis_options.yaml`. Key conventions:

- **Always declare return types** on functions and methods.
- **Use `final` for local variables** (`prefer_final_locals`).
- **Require trailing commas** in argument lists and collection literals.
- **Prefer relative imports** within the package.
- **Sort constructors first** in class declarations.

### Public API

- The public API is exported through `lib/firebase_functions.dart` (the barrel file). Only add exports there for types that users need directly.
- Classes in `lib/src/` are implementation details. They can be public (no underscore prefix) but should not be exported from the barrel file unless they are part of the public API.

### Documentation

- Add dartdoc (`///`) comments to all new public APIs.
- Include code examples in doc comments where they help clarify usage.

### Error Handling

- Use `HttpResponseException` from `package:google_cloud_shelf` (`badRequest`, `unauthorized`, `notFound`, etc.) for user-facing errors.
- Match the Node.js SDK error codes and behavior where applicable.

## Testing Requirements

- **All new features and bug fixes must include tests.**
- **Unit tests** go in `test/unit/`. Test components in isolation using `mocktail` for mocking.
- **Snapshot tests** validate that the Dart builder generates manifests compatible with the Node.js SDK. If your change affects YAML manifest generation, update or add snapshot tests in `test/snapshots/`.
- **E2E tests** in `test/e2e/` cover full request/response cycles against the Firebase Emulator. Add these for new trigger types or protocol changes.

See `test/snapshots/README.md` for details on the snapshot testing strategy.

## Pull Request Process

1. Create a feature branch from `main`.
2. Make your changes, including tests.
3. Run formatting, analysis, and tests locally (see commands above).
4. Push your branch and open a pull request.
5. Fill in the PR description:
   - **What** the change does and **why**.
   - Link to any related issues.
   - Note any breaking changes.
6. CI will run automatically. All checks must pass before merging.
7. A project maintainer will review and may request changes.

### Commit Messages

- Write clear, descriptive commit messages.
- Use imperative mood (e.g., "Add Pub/Sub retry support" not "Added Pub/Sub retry support").
- Reference issues with `#number` where applicable.

## CI/CD

The project has two GitHub Actions workflows:

- **test.yml** (push to `main`/`develop` and PRs): Runs lint + analysis, builder tests, snapshot tests, and E2E tests across stable and beta Dart SDKs.
- **pr-checks.yml** (PRs only): Fast validation with formatting, analysis, and snapshot checks.

See `.github/workflows/README.md` for full details on each job and how to debug failures.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
