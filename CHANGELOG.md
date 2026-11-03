# Changelog

All notable changes to claymod-libs-pkg are documented here. The format
is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

Status: **planned** — no immutable tag has been published yet.

### Added

- `pkg.Installed` — ensures packages are installed on apt, dnf/yum, apk,
  pacman and brew, with a native-query guard per backend.
- `pkg.Absent` — ensures packages are removed; `purge = true` is the
  explicit opt-in for configuration and orphaned-dependency removal.
- `pkg.Repo` — third-party deb/rpm repositories: HTTPS signing key, repo
  file, optional pin priority, and index refresh. Signature verification
  is on by default.
- `pkg.Updated` — package-index refresh with a portable TTL stamp.
- Hermetic test suite (`tests/run.sh`): evaluation, structural op
  assertions, stub-backed execution for all five backends, and
  evaluation-time refusal tests.
- Docker simulation (`tests/docker_simulate.sh`) for debian, fedora,
  alpine and archlinux in CI.
- CI: pkl validation, claymod CLI validation, and the distro matrix.
