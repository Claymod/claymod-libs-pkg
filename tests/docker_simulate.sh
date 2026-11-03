#!/bin/sh
# Runs the generated pkg recipes inside a real distribution image.
#
#   tests/docker_simulate.sh debian:12 tests/.build/playbook-ci.json
#
# Requires Docker and an evaluated tests/playbook.ci.pkl. CI runs this on
# every non-PR build for debian, fedora, alpine and archlinux; it is the
# only test that exercises real package managers end to end.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
IMAGE=${1:?usage: docker_simulate.sh <image> <playbook-ci.json>}
JSON=${2:?usage: docker_simulate.sh <image> <playbook-ci.json>}

command -v docker >/dev/null 2>&1 || {
  echo "docker_simulate: docker not found" >&2
  exit 2
}
command -v python3 >/dev/null 2>&1 || {
  echo "docker_simulate: python3 not found" >&2
  exit 2
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/claymod-pkg-sim.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

for resource in index tree-installed tree-absent; do
  for field in command unlessIf; do
    python3 "$ROOT/tests/extract.py" "$JSON" "$resource" "$field" "$WORK/$resource.$field.sh"
  done
done

docker run --rm \
  --label com.tidet.sandbox=true \
  -e SIM_IMAGE="$IMAGE" \
  -v "$WORK:/w:ro" \
  "$IMAGE" \
  sh -eu -c '
    echo "== $SIM_IMAGE: refresh the package index"
    sh /w/index.command.sh

    echo "== $SIM_IMAGE: install guard must want to run"
    if sh /w/tree-installed.unlessIf.sh; then
      echo "FAIL: the install guard skipped on a fresh image" >&2
      exit 1
    fi

    echo "== $SIM_IMAGE: install tree"
    sh /w/tree-installed.command.sh

    echo "== $SIM_IMAGE: install guard must now skip"
    sh /w/tree-installed.unlessIf.sh

    echo "== $SIM_IMAGE: absent guard must want to run"
    if sh /w/tree-absent.unlessIf.sh; then
      echo "FAIL: the absent guard skipped while tree was installed" >&2
      exit 1
    fi

    echo "== $SIM_IMAGE: remove tree"
    sh /w/tree-absent.command.sh

    echo "== $SIM_IMAGE: absent guard must now skip"
    sh /w/tree-absent.unlessIf.sh

    echo "simulation OK: $SIM_IMAGE"
  '
