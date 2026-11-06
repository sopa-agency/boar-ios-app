#!/usr/bin/env python3
"""Removes the keys no build uses from App/Resources/Localizable.xcstrings.

xcodebuild doesn't mark a key stale when its text changes in code, so the old key stays in the catalog. This keeps every
key the last builds extracted (*.stringsdata under .build/DerivedData) and the "manual" ones (looked up at run time),
and deletes the rest. Build both apps from a clean Boar.build first, so no stringsdata of a deleted file is left:

  rm -rf .build/DerivedData/Build/Intermediates.noindex/Boar.build
  xcodebuild ... -scheme Boar ... build && xcodebuild ... -scheme BoarMac ... build
  python3 scripts/prune-strings.py           # lists what it would delete
  python3 scripts/prune-strings.py --write   # deletes them
"""
import glob
import json
import os
import sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
path = os.path.join(root, "App/Resources/Localizable.xcstrings")
catalog = json.load(open(path))

used = set()
for data_path in glob.glob(os.path.join(root, ".build/DerivedData/Build/Intermediates.noindex/Boar.build/**/*.stringsdata"), recursive=True):
    for entry in json.load(open(data_path)).get("tables", {}).get("Localizable", []):
        used.add(entry["key"])
if not used:
    sys.exit("No stringsdata: build Boar and BoarMac first.")

stale = sorted(k for k, v in catalog["strings"].items() if k not in used and v.get("extractionState") != "manual")
for key in stale:
    print(key)
if "--write" in sys.argv:
    for key in stale:
        del catalog["strings"][key]
    # Xcode's layout (" : " separators, no trailing newline); the order stays as it was, so the diff is only deletions.
    with open(path, "w") as f:
        f.write(json.dumps(catalog, indent=2, separators=(",", " : "), ensure_ascii=False))
print(f"{len(stale)} stale keys" + (" deleted" if "--write" in sys.argv else ""), file=sys.stderr)
