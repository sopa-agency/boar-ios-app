#!/usr/bin/env python3
"""Lists the app's string keys with no Portuguese in App/Resources/Localizable.xcstrings.

xcodebuild doesn't add new keys to the catalog: this reads the keys the last build extracted (*.stringsdata under
.build/DerivedData) and prints each one missing from the catalog or without a "pt" translation, with where it is used.

  python3 scripts/missing-strings.py            # after an xcodebuild of Boar (and BoarMac)
  python3 scripts/missing-strings.py --json     # the same, as {key: "file:line"} for scripting
"""
import glob
import json
import os
import sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
catalog = json.load(open(os.path.join(root, "App/Resources/Localizable.xcstrings")))["strings"]

# Each source file's newest stringsdata (the iPhone, simulator and Mac builds each keep one; an older one is stale).
newest = {}
for path in glob.glob(os.path.join(root, ".build/DerivedData/Build/Intermediates.noindex/Boar.build/**/*.stringsdata"), recursive=True):
    data = json.load(open(path))
    source = data.get("source", path)
    if source not in newest or os.path.getmtime(path) > newest[source][0]:
        newest[source] = (os.path.getmtime(path), data)

used = {}
for source, (_, data) in newest.items():
    source = os.path.relpath(source, root)
    for entry in data.get("tables", {}).get("Localizable", []):
        used.setdefault(entry["key"], f"{source}:{entry.get('location', {}).get('startingLine', '?')}")


def has_pt(key):
    loc = catalog.get(key, {}).get("localizations", {}).get("pt", {})
    return "stringUnit" in loc or "variations" in loc


missing = {k: where for k, where in sorted(used.items()) if not has_pt(k) and k.strip()}
if "--json" in sys.argv:
    print(json.dumps(missing, ensure_ascii=False, indent=2))
else:
    for k, where in missing.items():
        print(f"{where}\t{k}")
    print(f"{len(missing)} without Portuguese", file=sys.stderr)
