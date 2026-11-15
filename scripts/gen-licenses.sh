#!/usr/bin/env bash
# gen-licenses.sh: writes Packages/NomiUI/Sources/NomiUI/Resources/Licenses.txt,
# the open-source licence text the Licences screen shows (S9b).
#
# Every entry is read from disk, nothing is typed in:
#   - each pin in Packages/*/Package.resolved, with its checkout's LICENSE
#     file and NOTICE file (when present) from Packages/<pkg>/.build/checkouts/;
#   - the Inter licence bundled in Packages/NomiUI/Sources/NomiUI/Resources/Fonts.
# A missing checkout or licence file stops the script with exit 1. Run
# `swift package resolve` in that package first to create its checkouts.
# The output has no timestamp, so a re-run with the same pins is byte-identical.
#
# Usage: scripts/gen-licenses.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="$REPO/Packages/NomiUI/Sources/NomiUI/Resources/Licenses.txt"
INTER="$REPO/Packages/NomiUI/Sources/NomiUI/Resources/Fonts/OFL-Inter.txt"

python3 -I - "$REPO" "$OUT" "$INTER" <<'PY'
import glob
import json
import os
import sys

repo, out, inter = sys.argv[1], sys.argv[2], sys.argv[3]


def fail(message):
    sys.stderr.write("gen-licenses: " + message + "\n")
    sys.exit(1)


def first_match(directory, pattern):
    matches = sorted(glob.glob(os.path.join(directory, pattern)))
    return matches[0] if matches else None


def read_text(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read().strip()


entries = {}
for resolved in sorted(glob.glob(os.path.join(repo, "Packages", "*", "Package.resolved"))):
    package_dir = os.path.dirname(resolved)
    with open(resolved, encoding="utf-8") as handle:
        pins = json.load(handle).get("pins", [])
    for pin in pins:
        name = os.path.basename(pin["location"].rstrip("/"))
        if name.endswith(".git"):
            name = name[: -len(".git")]
        version = pin.get("state", {}).get("version")
        if not version:
            fail("%s has no tagged version in %s; add the licence by hand after review" % (name, resolved))
        checkout = os.path.join(package_dir, ".build", "checkouts", name)
        if not os.path.isdir(checkout):
            fail("no checkout for %s at %s; run swift package resolve in %s first" % (name, checkout, package_dir))
        licence = first_match(checkout, "LICENSE*")
        if licence is None:
            fail("no LICENSE file in %s; stop and report, do not invent text" % checkout)
        notice = first_match(checkout, "NOTICE*")
        body = read_text(licence)
        if notice is not None:
            body += "\n\nNOTICE\n\n" + read_text(notice)
        entries.setdefault((name.lower(), version), (name, version, body))

if not os.path.isfile(inter):
    fail("missing bundled Inter licence at %s" % inter)

sections = [
    "Open-source licences in Nomi",
    "The licence text for each third-party package that Nomi ships, as it appears in that package.",
]
for key in sorted(entries):
    name, version, body = entries[key]
    sections.append("== %s %s ==\n\n%s" % (name, version, body))
sections.append("== Inter (bundled font) ==\n\n%s" % read_text(inter))

with open(out, "w", encoding="utf-8") as handle:
    handle.write("\n\n".join(sections) + "\n")
print("wrote %s: %d package entries and Inter" % (out, len(entries)))
PY
