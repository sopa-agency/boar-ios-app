#!/usr/bin/env python3
"""Checks Sources/BoarCore/Vault.swift against Android's engine/vault/Vault.kt at Fixtures/SOURCE_SHA.

Compares every rule's condition (Kotlin's lambda body against the Swift switch case, with .size read as .count and
LocalDate `d` as `today`) and the avatar -> rule table, in order. Run it after scripts/sync-reference.sh: a rule changed
on Android fails here. Usage: scripts/check-vault-rules.py [path/to/boar-app]   (default ../boar-app)
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT.parent / "boar-app"
SHA = (ROOT / "Fixtures/SOURCE_SHA").read_text().strip()
KT_PATH = "android-native/engine/src/main/java/team/sopa/boar/engine/vault/Vault.kt"

kt = subprocess.run(["git", "-C", str(APP), "show", f"{SHA}:{KT_PATH}"], check=True, capture_output=True, text=True).stdout
swift = (ROOT / "Sources/BoarCore/Vault.swift").read_text()


def norm(expr: str) -> str:
    expr = re.sub(r"\s+", " ", expr).strip()
    expr = expr.replace(".size", ".count")
    expr = re.sub(r",\s*d\)", ", today)", expr)
    return expr


kt_rules = {m.group(1): norm(m.group(2)) for m in re.finditer(r"^\s+([A-Z][A-Z0-9_]*)\(\{\s*\w+,\s*\w+\s*->\s*(.*?)\s*\}\),", kt, re.M)}
sw_rules = {m.group(1): norm(m.group(2)) for m in re.finditer(r"^\s+case \.([A-Z][A-Z0-9_]*): (.*)$", swift, re.M)}
kt_table = re.findall(r'"([a-z_]+)" to Rule\.([A-Z0-9_]+)', kt)
sw_table = re.findall(r'\("([a-z_]+)", \.([A-Z0-9_]+)\)', swift)

errors = []
if not kt_rules:
    errors.append("no rules found in Vault.kt (format changed?)")
for name in sorted(set(kt_rules) | set(sw_rules)):
    a, b = kt_rules.get(name), sw_rules.get(name)
    if a is None:
        errors.append(f"rule {name}: only in Swift")
    elif b is None:
        errors.append(f"rule {name}: only in Kotlin ({a})")
    elif a != b:
        errors.append(f"rule {name}: Kotlin `{a}` vs Swift `{b}`")
if kt_table != sw_table:
    for i, (a, b) in enumerate(zip(kt_table, sw_table)):
        if a != b:
            errors.append(f"avatar #{i}: Kotlin {a} vs Swift {b}")
    if len(kt_table) != len(sw_table):
        errors.append(f"avatars: Kotlin has {len(kt_table)}, Swift {len(sw_table)}")

if errors:
    print("\n".join(errors))
    sys.exit(1)
print(f"Vault rules match Android at {SHA[:8]}: {len(kt_rules)} rules, {len(kt_table)} avatars")
