#!/usr/bin/env python3
"""Build the Boar Avatars' app icons (android boar.truffleLauncherIcons, off by default) into
App/Resources/LauncherIcons.xcassets: one AppIcon-<id>.appiconset per boar, 1024 px PNG.

Same picture as Android's adaptive icon (scripts/build-truffle-icons.py in boar-app): the 512 px hi-res art at
android-native/art/icons/hires/<id>.webp, Fixtures/SOURCE_SHA, scaled so the visible area shows 288/300 of it (Android
paints the art 300 px wide where the launcher mask shows 288), so the art fills the icon edge to edge.

The catalog is git-ignored (40 PNGs are ~45 MB) and only builds with the flag on:

  python3 scripts/build-launcher-icons.py
  xcodegen generate
  then BOAR_LAUNCHER_ICONS = YES in Local.xcconfig (or on the xcodebuild command line)

With the flag off (the default), App.xcconfig excludes the catalog, so a leftover one changes nothing.
"""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT.parent / "boar-app"
ROSTER = ROOT / "Fixtures/vault/truffles.json"
OUT = ROOT / "App/Resources/LauncherIcons.xcassets"
HIRES = "android-native/art/icons/hires"
ICON = 1024
# Android: FG_ART 300 px of art where the mask shows 288 (72 dp at xxxhdpi).
SCALED = round(ICON * 300 / 288)


def git(*args: str) -> bytes:
    return subprocess.run(["git", "-C", str(APP), *args], check=True, capture_output=True).stdout


def sips(*args: str) -> None:
    subprocess.run(["sips", *args], check=True, capture_output=True)


def main() -> None:
    sha = (ROOT / "Fixtures/SOURCE_SHA").read_text().strip()
    ids = [icon["id"] for icon in json.loads(ROSTER.read_text())["icons"]]
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    (OUT / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    with tempfile.TemporaryDirectory() as tmp:
        for i in ids:
            src = Path(tmp) / f"{i}.webp"
            src.write_bytes(git("show", f"{sha}:{HIRES}/{i}.webp"))
            icon_set = OUT / f"AppIcon-{i}.appiconset"
            icon_set.mkdir()
            png = icon_set / "icon.png"
            sips("-s", "format", "png", "-z", str(SCALED), str(SCALED), str(src), "--out", str(png))
            sips("-c", str(ICON), str(ICON), str(png))
            contents = {
                "images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
                "info": {"author": "xcode", "version": 1},
            }
            (icon_set / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    total = sum(p.stat().st_size for p in OUT.rglob("*.png"))
    print(f"{len(ids)} app icons from {sha[:8]} into {OUT.relative_to(ROOT)} ({total / 1e6:.0f} MB)")


if __name__ == "__main__":
    sys.exit(main())
