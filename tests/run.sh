#!/bin/sh
# Full local test suite: evaluate the fixture, assert the generated ops,
# execute them against stub backends, then check the evaluation-time
# refusals. CI runs exactly this (see .github/workflows/ci.yml).
#
#   PKL=$(command -v pkl) CLAYMOD_SCHEMA=../claymod/pkl tests/run.sh
#
# CLAYMOD_SCHEMA defaults to .claymod/pkl when this checkout contains the
# main claymod repository (useful while developing side by side).
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
PKL=${PKL:-pkl}

if ! command -v "$PKL" >/dev/null 2>&1; then
  echo "tests: pkl CLI not found (set PKL=/path/to/pkl)" >&2
  exit 2
fi

CLAYMOD_SCHEMA=${CLAYMOD_SCHEMA:-}
if [ -z "$CLAYMOD_SCHEMA" ]; then
  if [ -d "$ROOT/.claymod/pkl" ]; then
    CLAYMOD_SCHEMA="$ROOT/.claymod/pkl"
  else
    echo "tests: set CLAYMOD_SCHEMA to a claymod checkout's pkl/ directory" >&2
    exit 2
  fi
fi

BUILD="$ROOT/tests/.build"
mkdir -p "$BUILD"

echo "== pkl eval"
"$PKL" eval --format json --color never \
  --module-path "$ROOT/pkl:$CLAYMOD_SCHEMA" \
  "$ROOT/tests/playbook.pkl" >"$BUILD/playbook.json"

echo "== generated ops"
python3 "$ROOT/tests/check_ops.py" "$BUILD/playbook.json"

echo "== shell recipes"
sh "$ROOT/tests/shell_tests.sh" "$BUILD/playbook.json"

echo "== evaluation-time refusals"
sh "$ROOT/tests/validate_errors.sh" "$PKL" "$CLAYMOD_SCHEMA"

if [ -n "${CLAYMOD:-}" ]; then
  echo "== claymod validate"
  (
    cd "$ROOT/tests"
    PATH="$(dirname "$PKL"):$PATH" "$CLAYMOD" playbook validate playbook.pkl
  )
fi

echo "tests: OK"
