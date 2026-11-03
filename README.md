# claymod-libs-pkg

Official claymod playbook library for **package management**: install and
remove packages, add third-party repositories with their signing keys, and
refresh the package index — on apt/dpkg, dnf/yum/rpm, apk, pacman and
brew.

| | |
|---|---|
| Module prefix | `pkg` |
| Module root | `pkl/` (pin with `path: pkl`) |
| Library index tier | **Official** — status: **planned**, no tags published yet |
| claymod | playbook schema v1 (`claymod.project.yaml` `version: 1`) |
| pkl | 0.32.2 (pinned in CI) |
| Backends | apt (deb), dnf/yum (rpm), apk (Alpine), pacman (Arch), brew (macOS) |
| License | [Apache-2.0](LICENSE) |

> **Status: planned.** The library index lists this repository as
> planned: designed and tested here, but no immutable tag has been
> published yet. Do not pin it in production playbooks until `v0.1.0`
> exists.

## Why this is a library, not part of the std

The shipped std holds what every Unix has: a file, a process, a user, a
listening port. A package manager depends on *which* package manager,
*which* distribution and *which* upstream channel a host runs, so it lives
here, versioned independently of the claymod binary.

## Install

```yaml
# claymod.project.yaml — in your playbook repo
version: 1
libraries:
  - name: pkg                       # import prefix: modulepath:/pkg/…
    git: https://github.com/Claymod/claymod-libs-pkg.git
    ref: v0.1.0                     # pin a tag or commit — always
    path: pkl
```

```pkl
// The alias is required: pkl derives the default alias from the file name
// ("packages"), and the API is used as pkg.*.
import "modulepath:/pkg/packages.pkl" as pkg
```

For local development, point `path` at this checkout instead of pinning a
git ref (`path: ../claymod-libs-pkg/pkl`); `claymod lib list` reports it
as a local library, `claymod lib sync` never touches the network.

## Quick start

```pkl
amends "modulepath:/claymod/base.pkl"

import "modulepath:/pkg/packages.pkl" as pkg

hosts {
  "web01"
  "web02"
}

resources {
  new pkg.Updated {
    name = "index"
    maxAgeMinutes = 60
  }

  new pkg.Installed {
    name = "web-packages"
    packages {
      "nginx"
      "curl"
    }
    dependsOn {
      "index"
    }
  }
}
```

The same playbook works on Debian, Fedora, Alpine, Arch and macOS: the
backend is detected **at run time on each host**, not in the playbook.

## Resources

All four resources compile to **one `std.commands.Shell` op each** — a
normal claymod operation with a guard. There is no hidden helper binary,
no Go module the agent has to know about, and `claymod playbook apply
--verbose` shows exactly what runs.

### `pkg.Installed`

Ensures a set of packages is installed.

| Field | Type | Default | Meaning |
|---|---|---|---|
| `packages` | `Listing<String>` | — | Packages that must be present. Required, non-empty. |
| `name`, `dependsOn` | inherited | — | Standard resource fields. |

```pkl
new pkg.Installed {
  name = "nginx"
  packages { "nginx" "curl" }
}
```

- Backend selection: `apt-get`, then `dnf`, then `yum`, then `apk`, then
  `pacman`, then `brew`. A host with none fails with a clear message.
- apt installs with `--no-install-recommends`; the other backends use
  their normal install command.
- Package names that are empty or start with `-` are refused at
  evaluation time (no option injection).

**Idempotence guarantee.** The guard asks the backend's native query —
`dpkg-query -W` / `rpm -q` / `apk info -e` / `pacman -Q` /
`brew list --versions` — about **every** listed package and skips the op
when all are installed. A second apply on a converged host reports
`changed = false` without running the installer.

### `pkg.Absent`

Ensures a set of packages is **not** installed.

| Field | Type | Default | Meaning |
|---|---|---|---|
| `packages` | `Listing<String>` | — | Packages that must be absent. Required, non-empty. |
| `purge` | `Boolean` | `false` | Also remove configuration and orphaned dependencies. |

```pkl
new pkg.Absent {
  name = "no-telnet"
  packages { "telnet" }
}
```

`purge = true` maps to `apt-get purge --auto-remove` and
`pacman -Rns`; the default is a plain remove (`apt-get remove`,
`dnf remove`, `yum remove`, `apk del`, `pacman -R`, `brew uninstall`).
Destructive extra removal is an explicit opt-in, never a default.

**Idempotence guarantee.** The guard skips the op when the native query
reports every package as already absent; the second apply reports
`changed = false`.

### `pkg.Repo`

Adds a third-party repository: signing key, repo file, optional pin, and
an index refresh.

| Field | Type | Default | Meaning |
|---|---|---|---|
| `url` | `String` | — | Repository base URL. Must be `https://`. |
| `key` | `String` | `""` | Signing-key URL (armored or binary). Must be `https://`; required unless `unsigned = true`. |
| `format` | `"deb"` \| `"rpm"` | `"deb"` | Repository format. |
| `suite` | `String` | `""` | deb suite/codename; empty = read `VERSION_CODENAME`/`UBUNTU_CODENAME` from `/etc/os-release`. |
| `components` | `String` | `"main"` | deb components (may contain spaces, e.g. `"main contrib non-free"`). |
| `keyring` | `String` | `""` | deb keyring path; empty = `/usr/share/keyrings/<slug>.gpg`. |
| `priority` | `Int` | `0` | deb: apt origin pin; rpm: dnf `priority=`. `0` = no pin. |
| `unsigned` | `Boolean` | `false` | Explicit opt-in for a repository without a key. |

```pkl
new pkg.Repo {
  name = "nginx-stable"
  url = "https://nginx.org/packages/debian"
  key = "https://nginx.org/keys/nginx_signing.key"
  format = "deb"
}

new pkg.Repo {
  name = "vendor-rpm"
  url = "https://packages.example.com/rpm/$releasever/$basearch"
  key = "https://packages.example.com/rpm/RPM-GPG-KEY"
  format = "rpm"
}
```

What it writes:

| Format | Files | Refresh |
|---|---|---|
| deb | `/etc/apt/sources.list.d/<slug>.list`, `/usr/share/keyrings/<slug>.gpg`, optionally `/etc/apt/preferences.d/<slug>.pref` | `apt-get update -qq` |
| rpm | `/etc/yum.repos.d/<slug>.repo` (key imported with `rpm --import`) | `dnf`/`yum makecache` |

`<slug>` is the resource name reduced to `[A-Za-z0-9_-]`, so a name can
never escape these directories. Keep repo resource names distinct: two
names that slug identically share files.

Key handling: the key is fetched with `curl --proto '=https'
--tlsv1.2`; an ASCII-armored key is dearmored with `gpg --dearmor`, a
binary key is installed as-is. A key that is not valid (bad URL, network
failure, missing `gpg`) fails the apply — nothing is silently skipped.

**Idempotence guarantee.** A state marker records the declared
configuration (`format`, URL, key URL, suite, components, keyring,
priority, unsigned). The guard skips the op only when the marker matches,
the repo file still contains the declared URL, and the deb keyring (and
pin file, when `priority > 0`) still exist. Changing any field re-applies;
re-applying with the same fields reports `changed = false`. The marker is
host-local state, not a secret.

### `pkg.Updated`

Refreshes the package **index** (metadata). It never upgrades a package.

| Field | Type | Default | Meaning |
|---|---|---|---|
| `maxAgeMinutes` | `Int` | `60` | Reuse a stamp younger than this. Must be at least 1. |

```pkl
new pkg.Updated {
  name = "index"
  maxAgeMinutes = 60
}
```

Refresh command: `apt-get update -qq`, `dnf/yum -q makecache`,
`apk update`, `pacman -Sy --noconfirm`, `brew update`.

**Idempotence guarantee.** The command writes a stamp on success; the
guard skips the op while the stamp is younger than `maxAgeMinutes`. This
is a TTL (the same idea as Ansible's `cache_valid_time`), not a claim that
the index is unchanged — package indexes change upstream by definition.
Use `maxAgeMinutes = 1` when a later `pkg.Installed` must see a fresh
index. The stamp is shared by every `pkg.Updated` resource on a host.

## Backend matrix

| Operation | apt | dnf/yum | apk | pacman | brew |
|---|---|---|---|---|---|
| Installed: probe | `dpkg-query -W` | `rpm -q` | `apk info -e` | `pacman -Q` | `brew list --versions` |
| Installed: apply | `apt-get install` | `dnf/yum install` | `apk add` | `pacman -S` | `brew install` |
| Absent: apply | `apt-get remove` | `dnf/yum remove` | `apk del` | `pacman -R` | `brew uninstall` |
| Absent: purge | `apt-get purge --auto-remove` | same as remove | same as remove | `pacman -Rns` | same as remove |
| Repo | sources.list + keyring | `.repo` + `rpm --import` | — | — | — |
| Updated | `apt-get update` | `makecache` | `apk update` | `pacman -Sy` | `brew update` |

`pkg.Repo` supports deb and rpm only: apk, pacman and brew have no
third-party repository file in the claymod model (their repositories are
configuration, not package resources).

## State written to hosts

| Path | Written by | Purpose |
|---|---|---|
| `/var/lib/claymod-libs-pkg/repos/<slug>.state` | `pkg.Repo` | Declared-configuration marker (root agents) |
| `/var/lib/claymod-libs-pkg/package-index.stamp` | `pkg.Updated`, `pkg.Repo` | Index freshness TTL |
| `/usr/share/keyrings/<slug>.gpg`, `/etc/apt/sources.list.d/<slug>.list`, `/etc/apt/preferences.d/<slug>.pref` | `pkg.Repo` (deb) | apt repository |
| `/etc/yum.repos.d/<slug>.repo` | `pkg.Repo` (rpm) | dnf/yum repository |

Non-root agents (brew on macOS) use
`$XDG_STATE_HOME/claymod-libs-pkg` (default `~/.local/state/...`) instead
of `/var/lib`. `CLAYMOD_LIBS_PKG_STATE` overrides both. The state
directory contains no secrets.

## Security

- **HTTPS only** for repository and key URLs; the playbook is refused at
  evaluation time otherwise, and `curl` is invoked with
  `--proto '=https'` as depth in depth.
- **Signature verification is on by default.** An unsigned repository is
  an explicit `unsigned = true` per resource, never a fallback.
- **No shell injection.** Every playbook-supplied value is single-quoted
  for `/bin/sh`; repo configuration fields are refused when they contain a
  newline (they are written to line-oriented files).
- **No option injection.** Package names must not be empty or start with
  `-`.
- **No secrets.** Signing keys are public by definition. Tokens and
  passwords do not belong in this library; pass them as playbook `vars`
  or per-host configuration.
- Package managers and `curl`/`gpg` run with the agent's privileges —
  normally root for host configuration. Review a library before pinning
  it, as with any playbook.

## Idempotence guarantees (summary)

| Resource | Guard | Second apply |
|---|---|---|
| `pkg.Installed` | Every package installed via the native query | `changed = false` |
| `pkg.Absent` | Every package absent via the native query | `changed = false` |
| `pkg.Repo` | Marker + repo file + keyring/pin file | `changed = false` |
| `pkg.Updated` | Index stamp younger than `maxAgeMinutes` | `changed = false` |

Every command recipe is a plain `std.commands.Shell` op, so the agent's
own guard semantics (`onlyIf`/`unlessIf` returning 0 → skipped,
`changed = false`) apply unchanged.

## Supported versions and testing

- **claymod**: playbook schema v1. The resources import
  `modulepath:/claymod/base.pkl` and emit `std.commands.Shell`; no module
  outside the shipped std is required.
- **pkl**: 0.32.2, pinned in CI.
- **Distributions**: CI is configured to run the generated recipes on
  `debian:12`, `debian:13`, `fedora:latest`, `alpine:latest` and
  `archlinux:latest`. The hermetic suite exercises all five backend
  recipes on every run (stub package managers, no network/root).
- The main claymod repository's `simulation/` covers enrollment and the
  agent protocol. Package behavior needs real package managers, so this
  library runs its own distro matrix in CI (non-PR builds):
  `tests/docker_simulate.sh`.

`pkg.Repo`'s file-writing path targets `/etc` and is therefore not run by
the hermetic suite; its recipes are asserted structurally
(`tests/check_ops.py`) and its evaluation-time refusals are tested. A
container job for it is on the roadmap.

## Development

```sh
# pkl + a claymod checkout (for the std schema)
PKL=/path/to/pkl \
CLAYMOD_SCHEMA=/path/to/claymod/pkl \
CLAYMOD=/path/to/claymod \
  sh tests/run.sh
```

| Layer | What it proves |
|---|---|
| `pkl eval` | The fixture evaluates against the real claymod schema |
| `tests/check_ops.py` | Every resource is a `std.commands.Shell` with the promised recipes |
| `tests/shell_tests.sh` | Guards/commands behave per backend, hermetically |
| `tests/validate_errors.sh` | Unsafe configurations are refused at evaluation time |
| `claymod playbook validate` | The fixture passes claymod's own validation and planning |

CI additionally builds the claymod CLI and runs the tests against it;
the Docker matrix runs on pushes and tags.

## Compatibility and releases

- Semantic versioning, immutable tags. A moved tag is a supply-chain
  incident, not a bug.
- Renames of a module path (`modulepath:/pkg/…`) or a resource name are
  major changes; the old name is kept and deprecated first.
- Additive fields are minor; changing a default is a minor with a note;
  removing a field is major.
- Security fixes ship as a patch on every supported minor line.

## License

[Apache-2.0](LICENSE).
