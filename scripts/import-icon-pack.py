#!/usr/bin/env python3
"""Import Android's Boar icon pack into the asset catalog as custom SF Symbols.

Reads .ref/android-native/app/src/main/res/drawable/ic_*.xml (vector drawables traced from the icon pack grid: one
path, one fill) and writes App/Resources/Assets.xcassets/Icons/<name>.symbolset: a symbol template with the same path
as its Regular glyph at the small, medium and large scales. As a symbol it scales with the text, sits on the baseline,
and takes the theme's tint where it's drawn (android PackIcon), like an SF Symbol. Other weights fall back to Regular.

The symbol name swaps the `ic_` prefix for `boar.` (the Icons folder adds no namespace): ic_settings_models.xml becomes
"boar.settings_models", BoarIcon.symbolName. It also writes
App/Sources/Theme/BoarIcon.swift, one case per symbol; views draw them as AppIcon.pack(.settingsModels).

Usage: python3 scripts/import-icon-pack.py   (refresh .ref first with scripts/sync-reference.sh)
"""
import json
import re
import shutil
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / ".ref/android-native/app/src/main/res/drawable"
OUT = ROOT / "App/Resources/Assets.xcassets/Icons"
SWIFT = ROOT / "App/Sources/Theme/BoarIcon.swift"
ANDROID = "{http://schemas.android.com/apk/res/android}"
# Android-only: the notification's status bar icon.
SKIP = {"ic_stat_answering"}

# The symbol template's medium scale (Template v.3.0, 100 pt): baseline and cap line, in template units.
BASELINE_M = 1126.0
CAP_HEIGHT = 70.459
LEFT = 1400.0
# The drawable's viewport (24 dp, the whole box) becomes a 98-unit square centred on the cap height. The traced
# glyphs fill about 88% of it, so they come out about as big as SF Symbols' circle at the same point size (~86) and
# pack glyphs and SF Symbols read alike next to each other.
BOX = 98.0
# The small and large image scales, as SF Symbols draws them (circle at 100 pt: 93, 118 and 150 wide), each on its own
# baseline. Every scale must be in the template: iOS asks a list row's and a toolbar's icons for the large one and
# draws nothing when it's missing.
SCALES = {"S": (696.0, 93 / 118), "M": (BASELINE_M, 1.0), "L": (1556.0, 150 / 118)}

TOKEN = re.compile(r"[MmLlHhVvCcSsQqTtZz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")


def absolute(d: str) -> str:
    """The path with every command made absolute and only M, L, C and Z left (the drawables use M L H V C Z)."""
    tokens = TOKEN.findall(d)
    out: list[str] = []
    i, cmd = 0, None
    x = y = sx = sy = 0.0

    def num() -> float:
        nonlocal i
        v = float(tokens[i])
        i += 1
        return v

    while i < len(tokens):
        if tokens[i].isalpha():
            cmd = tokens[i]
            i += 1
        rel = cmd.islower()
        c = cmd.upper()
        if c == "Z":
            out.append(("Z", ()))
            x, y = sx, sy
            continue
        if c == "M":
            nx, ny = num(), num()
            if rel:
                nx, ny = x + nx, y + ny
            out.append(("M", (nx, ny)))
            x, y, sx, sy = nx, ny, nx, ny
            cmd = "l" if rel else "L"  # extra pairs after M are line-tos
        elif c == "L":
            nx, ny = num(), num()
            if rel:
                nx, ny = x + nx, y + ny
            out.append(("L", (nx, ny)))
            x, y = nx, ny
        elif c == "H":
            nx = num() + (x if rel else 0)
            out.append(("L", (nx, y)))
            x = nx
        elif c == "V":
            ny = num() + (y if rel else 0)
            out.append(("L", (x, ny)))
            y = ny
        elif c == "C":
            pts = [num() for _ in range(6)]
            if rel:
                pts = [p + (x if k % 2 == 0 else y) for k, p in enumerate(pts)]
            out.append(("C", tuple(pts)))
            x, y = pts[4], pts[5]
        else:
            sys.exit(f"unsupported path command {cmd}")
    return out


def glyph(drawable: Path, box: float) -> tuple[str, float]:
    """The drawable's path as a glyph `box` units tall (origin on the left margin and the baseline), and its width."""
    root = ET.parse(drawable).getroot()
    w, h = float(root.get(ANDROID + "viewportWidth")), float(root.get(ANDROID + "viewportHeight"))
    paths = root.findall("path")
    if len(paths) != 1 or root.find("group") is not None:
        sys.exit(f"{drawable.name}: expected one path and no groups")
    if paths[0].get(ANDROID + "fillType") != "evenOdd":
        sys.exit(f"{drawable.name}: expected an even-odd fill")
    k = box / max(w, h)
    top = -CAP_HEIGHT / 2 - h * k / 2

    def fmt(v: float) -> str:
        return f"{v:.3f}".rstrip("0").rstrip(".")

    parts = []
    for c, pts in absolute(paths[0].get(ANDROID + "pathData")):
        xy = [fmt(p * k + (0 if n % 2 == 0 else top)) for n, p in enumerate(pts)]
        parts.append(c + " ".join(xy))
    return "".join(parts), w * k


def template(drawable: Path) -> str:
    """Apple's symbol template (v3.0) with a Regular glyph at each scale, kept even-odd like the drawable (its holes).
    Other weights fall back to Regular."""
    guides, symbols = [], []
    for scale, (base, factor) in SCALES.items():
        path, width = glyph(drawable, BOX * factor)
        guides.append(f'  <line id="Baseline-{scale}" style="fill:none;stroke:#27AAE1;stroke-width:0.5;" '
                      f'x1="263" x2="3036" y1="{base}" y2="{base}"/>')
        guides.append(f'  <line id="Capline-{scale}" style="fill:none;stroke:#27AAE1;stroke-width:0.5;" '
                      f'x1="263" x2="3036" y1="{base - CAP_HEIGHT:.3f}" y2="{base - CAP_HEIGHT:.3f}"/>')
        for side, x in (("left", LEFT), ("right", LEFT + width)):
            guides.append(f'  <line id="{side}-margin-Regular-{scale}" style="fill:none;stroke:#00AEEF;stroke-width:0.5;" '
                          f'x1="{x:.3f}" x2="{x:.3f}" y1="{base - 96}" y2="{base + 24}"/>')
        symbols.append(f'  <g id="Regular-{scale}" transform="matrix(1 0 0 1 {LEFT} {base})">\n'
                       f'   <path fill-rule="evenodd" d="{path}"/>\n  </g>')
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<!-- Generated by scripts/import-icon-pack.py from Android's Boar icon pack. -->
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" width="3300" height="2200">
 <g id="Notes">
  <rect height="2200" id="artboard" style="fill:white;opacity:1" width="3300" x="0" y="0"/>
  <text id="template-version" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 3036 1933)">Template v.3.0</text>
 </g>
 <g id="Guides">
{chr(10).join(guides)}
 </g>
 <g id="Symbols">
{chr(10).join(symbols)}
 </g>
</svg>
'''


def main() -> None:
    if not SRC.is_dir():
        sys.exit(f"{SRC} not found: run scripts/sync-reference.sh first")
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    (OUT / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}) + "\n")
    names = []
    for drawable in sorted(SRC.glob("ic_*.xml")):
        if drawable.stem in SKIP:
            continue
        name = drawable.stem.removeprefix("ic_")
        folder = OUT / f"boar.{name}.symbolset"
        folder.mkdir()
        (folder / f"boar.{name}.svg").write_text(template(drawable))
        contents = {"info": {"author": "xcode", "version": 1}, "symbols": [{"filename": f"boar.{name}.svg", "idiom": "universal"}]}
        (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
        names.append(name)
    SWIFT.write_text(swift_enum(names))
    print(f"{len(names)} icons -> {OUT.relative_to(ROOT)}, {SWIFT.relative_to(ROOT)}")


def swift_enum(names: list[str]) -> str:
    def case(name: str) -> str:
        head, *rest = name.split("_")
        camel = head + "".join(p.capitalize() for p in rest)
        return f"    case {camel}" if camel == name else f'    case {camel} = "{name}"'

    cases = "\n".join(case(n) for n in names)
    return f"""// Generated by scripts/import-icon-pack.py: don't edit.

/// Android's Boar icon pack (res/drawable/ic_*.xml), one case per custom symbol in Assets.xcassets/Icons. Drawn
/// through AppIcon.pack.
enum BoarIcon: String, CaseIterable, Sendable {{
{cases}
}}
"""


if __name__ == "__main__":
    main()
