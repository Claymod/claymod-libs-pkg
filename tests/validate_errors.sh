#!/bin/sh
# Evaluation-time validation tests: classes that must refuse to evaluate.
# A rejected playbook is better than a host with a plaintext repository or
# an unguarded package removal.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
PKL=${1:?usage: validate_errors.sh <pkl-binary> <claymod-schema-dir>}
SCHEMA=${2:?usage: validate_errors.sh <pkl-binary> <claymod-schema-dir>}

BUILD="$ROOT/tests/.build/invalid"
mkdir -p "$BUILD"

check() {
  fixture=$1
  pattern=$2
  out="$BUILD/$fixture.log"
  if "$PKL" eval --format json --color never \
    --module-path "$ROOT/pkl:$SCHEMA" \
    "$ROOT/tests/invalid/$fixture.pkl" >"$out" 2>&1; then
    echo "FAIL: invalid/$fixture.pkl evaluated successfully (expected an error)" >&2
    exit 1
  fi
  if ! grep -qF -- "$pattern" "$out"; then
    echo "FAIL: invalid/$fixture.pkl error does not contain: $pattern" >&2
    sed 's/^/  /' "$out" >&2
    exit 1
  fi
}

check plaintext-url "url must start with https://"
check plaintext-key "key must start with https://"
check dash-package "must not start with '-'"
check unsigned-with-key "unsigned = true and key are mutually exclusive"
check missing-key 'key is required unless unsigned = true'
check rpm-keyring "keyring is only meaningful for format"
check empty-packages "packages must not be empty"
check bad-max-age "maxAgeMinutes must be >= 1"
check newline-url "url must be a single line"

echo "validate_errors: OK"
