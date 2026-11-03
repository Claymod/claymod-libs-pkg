#!/bin/sh
# Hermetic execution tests for the generated pkg recipes.
#
# The playbook fixture is evaluated by pkl (tests/run.sh), then the
# `command` and `unlessIf` strings are executed against stub package
# managers on a PATH that contains nothing else. That proves, for every
# supported backend, that:
#
#   - the guard asks the native query and reports "run" while a package is
#     missing, and "skip" once it is installed;
#   - the command invokes the right installer with the right arguments;
#   - removing packages and the purge opt-in behave as documented;
#   - the index TTL stamp works and goes stale.
#
# No root, no network, no container. Repo file writing (which targets
# /etc) is asserted structurally by tests/check_ops.py and exercised by
# the Docker simulation in CI, never here.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
JSON=${1:-"$ROOT/tests/.build/playbook.json"}
if [ ! -f "$JSON" ]; then
  echo "shell_tests: $JSON not found (run tests/run.sh)" >&2
  exit 2
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/claymod-pkg-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

REAL_PATH=$PATH
CASE=""
BIN=""

# A case gets its own bin/ and state/, so backends never see each other.
new_case() {
  CASE="$WORK/$1"
  BIN="$CASE/bin"
  mkdir -p "$BIN" "$CASE/state/installed"
  for tool in sh find id mkdir cat grep mktemp rm chmod cp touch; do
    resolved=$(PATH=$REAL_PATH command -v "$tool") || {
      echo "shell_tests: required tool '$tool' not found" >&2
      exit 2
    }
    ln -s "$resolved" "$BIN/$tool"
  done
}

# stub <names...> — symlink the fake backend under each command name.
stub() {
  for name in "$@"; do
    ln -s "$ROOT/tests/stub.sh" "$BIN/$name"
  done
}

run() {
  env PATH="$BIN" FAKE_PKG_STATE="$CASE/state" CLAYMOD_LIBS_PKG_STATE="$CASE/state" sh "$@"
}

expect_rc() {
  description=$1
  want=$2
  shift 2
  set +e
  run "$@" >"$CASE/stdout" 2>"$CASE/stderr"
  got=$?
  set -e
  if [ "$got" -ne "$want" ]; then
    echo "FAIL: $description (exit $got, want $want)" >&2
    sed 's/^/  out: /' "$CASE/stdout" >&2 || true
    sed 's/^/  err: /' "$CASE/stderr" >&2 || true
    exit 1
  fi
}

expect_log() {
  if ! grep -qF -- "$1" "$CASE/state/log" 2>/dev/null; then
    echo "FAIL: expected the backend log to contain: $1" >&2
    cat "$CASE/state/log" >&2 2>/dev/null || true
    exit 1
  fi
}

reject_log() {
  if grep -qF -- "$1" "$CASE/state/log" 2>/dev/null; then
    echo "FAIL: backend log must not contain: $1" >&2
    cat "$CASE/state/log" >&2 || true
    exit 1
  fi
}

preinstall() {
  : >"$CASE/state/installed/$1"
}

expect_file() {
  [ -f "$1" ] || {
    echo "FAIL: expected file $1 to exist" >&2
    exit 1
  }
}

# Fail with the captured stderr of a command that was supposed to succeed.
expect_contains() {
  grep -qF -- "$2" "$1" || {
    echo "FAIL: expected $1 to contain: $2" >&2
    cat "$1" >&2
    exit 1
  }
}

# --- extract and syntax-check every generated recipe --------------------
for resource in index repo-deb repo-rpm installed absent absent-purge; do
  for field in command unlessIf; do
    python3 "$ROOT/tests/extract.py" "$JSON" "$resource" "$field" "$WORK/$resource.$field.sh"
    sh -n "$WORK/$resource.$field.sh" || {
      echo "FAIL: syntax error in $resource.$field" >&2
      exit 1
    }
  done
done

# --- pkg.Installed: every backend --------------------------------------
new_case apt-install
stub apt-get dpkg-query
expect_rc "installed/apt: guard runs while packages are missing" 1 "$WORK/installed.unlessIf.sh"
expect_rc "installed/apt: install" 0 "$WORK/installed.command.sh"
expect_log "apt-get install -y --no-install-recommends nginx curl"
expect_rc "installed/apt: guard skips once converged" 0 "$WORK/installed.unlessIf.sh"

new_case apt-converged
stub apt-get dpkg-query
preinstall nginx
preinstall curl
expect_rc "installed/apt: already-converged host is skipped" 0 "$WORK/installed.unlessIf.sh"

new_case dnf-install
stub dnf rpm
expect_rc "installed/dnf: guard runs" 1 "$WORK/installed.unlessIf.sh"
expect_rc "installed/dnf: install" 0 "$WORK/installed.command.sh"
expect_log "dnf install -y nginx curl"
expect_rc "installed/dnf: guard skips once converged" 0 "$WORK/installed.unlessIf.sh"

new_case yum-install
stub yum rpm
expect_rc "installed/yum: install" 0 "$WORK/installed.command.sh"
expect_log "yum install -y nginx curl"
expect_rc "installed/yum: guard skips once converged" 0 "$WORK/installed.unlessIf.sh"

new_case apk-install
stub apk
expect_rc "installed/apk: install" 0 "$WORK/installed.command.sh"
expect_log "apk add --no-cache nginx curl"
expect_rc "installed/apk: guard skips once converged" 0 "$WORK/installed.unlessIf.sh"

new_case pacman-install
stub pacman
expect_rc "installed/pacman: install" 0 "$WORK/installed.command.sh"
expect_log "pacman -S --noconfirm --needed nginx curl"
expect_rc "installed/pacman: guard skips once converged" 0 "$WORK/installed.unlessIf.sh"

new_case brew-install
stub brew
expect_rc "installed/brew: install" 0 "$WORK/installed.command.sh"
expect_log "brew install nginx curl"
expect_rc "installed/brew: guard skips once converged" 0 "$WORK/installed.unlessIf.sh"

# --- pkg.Absent: remove and the purge opt-in ---------------------------
new_case apt-absent
stub apt-get dpkg-query
preinstall telnet
expect_rc "absent/apt: guard runs while installed" 1 "$WORK/absent.unlessIf.sh"
expect_rc "absent/apt: remove" 0 "$WORK/absent.command.sh"
expect_log "apt-get remove -y telnet"
reject_log "purge"
expect_rc "absent/apt: guard skips once absent" 0 "$WORK/absent.unlessIf.sh"

new_case apt-absent-skip
stub apt-get dpkg-query
expect_rc "absent/apt: already-absent host is skipped" 0 "$WORK/absent.unlessIf.sh"

new_case apt-purge
stub apt-get dpkg-query
preinstall telnet
expect_rc "absent/apt: purge" 0 "$WORK/absent-purge.command.sh"
expect_log "apt-get purge -y --auto-remove telnet"
expect_rc "absent/apt: purge guard skips once absent" 0 "$WORK/absent-purge.unlessIf.sh"

new_case pacman-purge
stub pacman
preinstall telnet
expect_rc "absent/pacman: purge" 0 "$WORK/absent-purge.command.sh"
expect_log "pacman -Rns --noconfirm telnet"

# --- pkg.Updated: TTL stamp --------------------------------------------
updated_case() {
  label=$1
  shift
  new_case "updated-$label"
  stub "$@"
  expect_rc "updated/$label: guard runs without a stamp" 1 "$WORK/index.unlessIf.sh"
  expect_rc "updated/$label: refresh" 0 "$WORK/index.command.sh"
  expect_file "$CASE/state/package-index.stamp"
  expect_rc "updated/$label: guard skips with a fresh stamp" 0 "$WORK/index.unlessIf.sh"
}

updated_case apt apt-get
expect_log "apt-get update -qq"
updated_case dnf dnf
expect_log "dnf -q makecache"
updated_case yum yum
expect_log "yum -q makecache"
updated_case apk apk
expect_log "apk update"
updated_case pacman pacman
expect_log "pacman -Sy --noconfirm"
updated_case brew brew
expect_log "brew update"

new_case updated-stale
stub apt-get
: >"$CASE/state/package-index.stamp"
touch -t 202001010000 "$CASE/state/package-index.stamp"
expect_rc "updated/apt: a stamp older than maxAgeMinutes is ignored" 1 "$WORK/index.unlessIf.sh"

# --- no backend at all -------------------------------------------------
new_case no-backend
expect_rc "installed: no supported backend fails" 1 "$WORK/installed.command.sh"
expect_contains "$CASE/stderr" "no supported package manager"
expect_rc "installed: guard reports run without a backend" 1 "$WORK/installed.unlessIf.sh"

echo "shell_tests: OK"
