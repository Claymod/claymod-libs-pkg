#!/usr/bin/env python3
"""Extract one field of one resource from an evaluated claymod playbook.

Usage: extract.py <playbook.json> <resource-name> <field> <output-file>

Exits non-zero with a clear message when the resource or field is missing,
so the shell harness fails loudly instead of testing an empty file.
"""
import json
import sys


def main() -> int:
    if len(sys.argv) != 5:
        print(
            "usage: extract.py <playbook.json> <resource-name> <field> <output-file>",
            file=sys.stderr,
        )
        return 2
    path, resource_name, field, out_path = sys.argv[1:5]
    with open(path, encoding="utf-8") as handle:
        document = json.load(handle)
    matches = [r for r in document.get("resources", []) if r.get("name") == resource_name]
    if len(matches) != 1:
        print(f"extract: expected one resource named {resource_name!r}, found {len(matches)}", file=sys.stderr)
        return 1
    value = matches[0].get(field)
    if not isinstance(value, str) or value == "":
        print(f"extract: {resource_name}.{field} is missing or not a non-empty string", file=sys.stderr)
        return 1
    with open(out_path, "w", encoding="utf-8") as handle:
        handle.write(value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
