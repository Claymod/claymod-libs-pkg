#!/bin/sh
# Fake package-manager backends for tests/shell_tests.sh.
#
# The harness symlinks this script under the name of each command it
# impersonates (apt-get, dpkg-query, dnf, yum, rpm, apk, pacman, brew,
# curl, gpg, install). Installed packages are files under
# $FAKE_PKG_STATE/installed/, so the tests can simulate convergence
# without a container, a network or root.
set -eu

name=${0##*/}
state=${FAKE_PKG_STATE:?FAKE_PKG_STATE must be set}
installed="$state/installed"
mkdir -p "$installed"
printf '%s %s\n' "$name" "$*" >>"$state/log"

mark() { : >"$installed/$1"; }
unmark() { rm -f "$installed/$1"; }
has() { [ -f "$installed/$1" ]; }
last_arg() { last=""; for a in "$@"; do last=$a; done; printf '%s' "$last"; }

# apply <install|remove> pkgs...  — every non-option argument is a package.
apply() {
  mode=$1
  shift
  for p in "$@"; do
    case "$p" in
      -*) ;;
      *) if [ "$mode" = install ]; then mark "$p"; else unmark "$p"; fi ;;
    esac
  done
}

case "$name" in
  apt-get)
    action=${1:?apt-get needs an action}
    shift
    case "$action" in
      update) : >"$state/apt-updated" ;;
      install) apply install "$@" ;;
      remove | purge) apply remove "$@" ;;
      *) echo "stub apt-get: unsupported action $action" >&2; exit 2 ;;
    esac
    ;;
  dpkg-query)
    pkg=$(last_arg "$@")
    if has "$pkg"; then printf 'install ok installed\n'; else exit 1; fi
    ;;
  dnf | yum)
    case "${1:-}" in
      -q)
        action=${2:-}
        shift 2
        ;;
      *)
        action=${1:-}
        shift
        ;;
    esac
    case "$action" in
      makecache) : >"$state/$name-makecache" ;;
      install) apply install "$@" ;;
      remove) apply remove "$@" ;;
      *) echo "stub $name: unsupported action $action" >&2; exit 2 ;;
    esac
    ;;
  rpm)
    case "${1:-}" in
      --import) : >"$state/rpm-imported" ;;
      -q)
        pkg=${2:?rpm -q needs a package}
        if has "$pkg"; then echo "$pkg"; else exit 1; fi
        ;;
      *) echo "stub rpm: unsupported $*" >&2; exit 2 ;;
    esac
    ;;
  apk)
    action=${1:?apk needs an action}
    shift
    case "$action" in
      update) : >"$state/apk-updated" ;;
      add) apply install "$@" ;;
      del) apply remove "$@" ;;
      info)
        pkg=$(last_arg "$@")
        if has "$pkg"; then echo "$pkg"; else exit 1; fi
        ;;
      *) echo "stub apk: unsupported action $action" >&2; exit 2 ;;
    esac
    ;;
  pacman)
    action=${1:?pacman needs an action}
    shift
    case "$action" in
      -Sy) : >"$state/pacman-updated" ;;
      -S) apply install "$@" ;;
      -R | -Rns) apply remove "$@" ;;
      -Q)
        pkg=${1:?pacman -Q needs a package}
        if has "$pkg"; then echo "$pkg"; else exit 1; fi
        ;;
      *) echo "stub pacman: unsupported action $action" >&2; exit 2 ;;
    esac
    ;;
  brew)
    action=${1:?brew needs an action}
    shift
    case "$action" in
      update) : >"$state/brew-updated" ;;
      install) apply install "$@" ;;
      uninstall) apply remove "$@" ;;
      list)
        pkg=$(last_arg "$@")
        if has "$pkg"; then echo "$pkg"; else exit 1; fi
        ;;
      *) echo "stub brew: unsupported action $action" >&2; exit 2 ;;
    esac
    ;;
  curl)
    out=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -o)
          out=$2
          shift 2
          ;;
        *) shift ;;
      esac
    done
    [ -n "$out" ] || { echo "stub curl: no -o output" >&2; exit 2; }
    printf '%s\n' '-----BEGIN PGP PUBLIC KEY BLOCK-----' 'fake-key' '-----END PGP PUBLIC KEY BLOCK-----' >"$out"
    ;;
  gpg)
    out=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -o)
          out=$2
          shift 2
          ;;
        *) shift ;;
      esac
    done
    [ -n "$out" ] || { echo "stub gpg: no -o output" >&2; exit 2; }
    cat >"$out"
    ;;
  install)
    if [ "${1:-}" = "-m" ]; then shift 2; fi
    cp "$1" "$2"
    ;;
  *)
    echo "stub: unsupported command $name" >&2
    exit 2
    ;;
esac
