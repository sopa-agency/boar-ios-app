#!/usr/bin/env python3
"""Adds Portuguese to App/Resources/Localizable.xcstrings from a JSON file of {"English key": "Portuguese"}.

Keeps Xcode's layout (keys sorted, " : " separators, no trailing newline), so the diff shows only the new strings.
A key already in the catalog gets its "pt" set; the English source stays implicit (the key), as Xcode leaves it.

  python3 scripts/add-strings.py new-pt.json
"""
import json
import os
import sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
path = os.path.join(root, "App/Resources/Localizable.xcstrings")
catalog = json.load(open(path))
added = json.load(open(sys.argv[1]))

for key, pt in added.items():
    entry = catalog["strings"].setdefault(key, {})
    entry.setdefault("localizations", {})["pt"] = {"stringUnit": {"state": "translated", "value": pt}}

catalog["strings"] = dict(sorted(catalog["strings"].items()))
with open(path, "w") as f:
    f.write(json.dumps(catalog, indent=2, separators=(",", " : "), ensure_ascii=False))
print(f"{len(added)} strings with Portuguese")
