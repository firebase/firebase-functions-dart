#!/usr/bin/env bash
#
# Builds a standalone, deployable copy of this example.
#
# Two things stop the example from deploying as it sits in the repo:
#
#   1. Its pubspec uses `resolution: workspace`, which needs the repo root.
#      Only the source directory is uploaded, so pub fails in the cloud build.
#   2. It depends on `firebase_functions` from pub.dev, which is the released
#      version and does not contain unreleased local changes.
#
# This script copies the example somewhere else and rewrites the pubspec to fix
# both, pointing at a git ref of your choice.
#
# Usage:
#   ./prepare-deploy.sh <git-ref> [output-dir]
#
#   ./prepare-deploy.sh feat/cors
#   ./prepare-deploy.sh feat/cors ~/tmp/cors-deploy
#
# The ref must already be pushed. To deploy the repo you are sitting in, push
# your branch first.

set -euo pipefail

REF="${1:-}"
OUT="${2:-$(mktemp -d)/cors-deploy}"
REPO="${CORS_DEMO_REPO:-https://github.com/firebase/firebase-functions-dart.git}"

if [ -z "$REF" ]; then
  sed -n '3,23p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
fi

SRC="$(cd "$(dirname "$0")" && pwd)"

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
cp -R "$SRC" "$OUT"
rm -rf "$OUT/.dart_tool" "$OUT/functions.yaml" "$OUT/build"

python3 - "$OUT/pubspec.yaml" "$REPO" "$REF" <<'PY'
import sys, pathlib

pubspec, repo, ref = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = pubspec.read_text()

# Standalone: no workspace root will exist beside the uploaded source.
text = text.replace('\nresolution: workspace\n', '\n')

# Resolve the SDK from the branch under test rather than from pub.dev.
text += f"""
dependency_overrides:
  firebase_functions:
    git:
      url: {repo}
      ref: {ref}
"""
pubspec.write_text(text)
print(f"  pubspec rewritten -> firebase_functions @ {ref}")
PY

echo "  prepared in $OUT"
echo
echo "Next:"
echo "  cd $OUT"
echo "  dart pub get"
echo "  dart run build_runner build --delete-conflicting-outputs"
echo "  firebase deploy --only functions --project YOUR_PROJECT"
