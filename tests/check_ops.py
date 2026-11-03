#!/usr/bin/env python3
"""Structural assertions over the evaluated pkg fixture.

Run after `pkl eval` (tests/run.sh): every pkg resource must compile to a
single std.commands.Shell op whose guard and command contain the recipes
this library promises. This is the fast, backend-independent half of the
test suite; tests/shell_tests.sh executes the same recipes against stub
backends.
"""
import json
import sys

RESOURCES = ("index", "repo-deb", "repo-rpm", "installed", "absent", "absent-purge")

failures: list[str] = []


def check(condition: bool, message: str) -> None:
    if not condition:
        failures.append(message)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check_ops.py <playbook.json>", file=sys.stderr)
        return 2
    with open(sys.argv[1], encoding="utf-8") as handle:
        document = json.load(handle)

    resources = {r.get("name"): r for r in document.get("resources", [])}
    check(sorted(resources) == sorted(RESOURCES), f"expected resources {RESOURCES}, got {sorted(resources)}")

    for name in RESOURCES:
        resource = resources.get(name)
        if resource is None:
            continue
        check(resource.get("type") == "std.commands.Shell", f"{name}: type is {resource.get('type')!r}, want std.commands.Shell")
        for field in ("command", "unlessIf"):
            value = resource.get(field, "")
            check(isinstance(value, str) and value != "", f"{name}: {field} is empty")
            check("\\(" not in value, f"{name}: {field} contains an unresolved pkl interpolation")

    installed = resources.get("installed", {})
    guard = installed.get("unlessIf", "")
    command = installed.get("command", "")
    for probe in ("dpkg-query", "rpm -q", "apk info -e", "pacman -Q", "brew list --versions"):
        check(probe in guard, f"installed: guard lacks the {probe!r} native query")
    for installer in ("apt-get install -y --no-install-recommends", "dnf install -y", "yum install -y", "apk add --no-cache", "pacman -S --noconfirm --needed", "brew install"):
        check(installer in command, f"installed: command lacks {installer!r}")
    check(installed.get("dependsOn") == ["repo-deb"], "installed: dependsOn should be ['repo-deb']")

    absent = resources.get("absent", {})
    check("apt-get remove -y" in absent.get("command", ""), "absent: expected a plain remove")
    check("purge" not in absent.get("command", ""), "absent: purge must be opt-in")

    purge = resources.get("absent-purge", {})
    check("apt-get purge -y --auto-remove" in purge.get("command", ""), "absent-purge: expected apt purge")
    check("pacman -Rns --noconfirm" in purge.get("command", ""), "absent-purge: expected pacman -Rns")

    deb = resources.get("repo-deb", {})
    deb_command = deb.get("command", "")
    deb_guard = deb.get("unlessIf", "")
    check("signed-by=/usr/share/keyrings/repo-deb.gpg" in deb_command, "repo-deb: signed-by option missing")
    check("apt-get update -qq" in deb_command, "repo-deb: index refresh missing")
    check("Pin-Priority" in deb_command, "repo-deb: pin priority missing")
    check("deb [%s] %s %s %s" in deb_command, "repo-deb: repo file recipe missing")
    check("[ -s '/usr/share/keyrings/repo-deb.gpg' ]" in deb_guard, "repo-deb: guard does not check the keyring")
    check("[ -f '/etc/apt/preferences.d/repo-deb.pref' ]" in deb_guard, "repo-deb: guard does not check the pin file")

    rpm = resources.get("repo-rpm", {})
    rpm_command = rpm.get("command", "")
    check("rpm --import" in rpm_command, "repo-rpm: key import missing")
    check("gpgcheck" in rpm_command, "repo-rpm: gpgcheck missing")
    check("makecache" in rpm_command, "repo-rpm: index refresh missing")
    check("'https://packages.example.com/rpm/$releasever/$basearch'" in rpm_command, "repo-rpm: baseurl must stay literal")

    updated = resources.get("index", {})
    check("-mmin -45" in updated.get("unlessIf", ""), "index: TTL guard missing")

    if failures:
        print("check_ops: FAILED", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1
    print(f"check_ops: OK ({len(RESOURCES)} resources)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
