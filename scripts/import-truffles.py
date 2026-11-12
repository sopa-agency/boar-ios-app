#!/usr/bin/env python3
"""Import the Boar Avatars' art (Android's truffles) into the app.

Reads the roster from Fixtures/vault/truffles.json (written by scripts/sync-reference.sh) and each boar's hi-res art
from boar-app's android-native/art/icons/hires/<id>.webp at Fixtures/SOURCE_SHA (512 px, square, opaque; Android's
in-app drawables are the same art at 256 px, too soft for a grid cell at 3x). Writes App/Resources/Boars/truffle_<id>.heic
(Android's drawable names), which TruffleArt loads from the bundle.

Loose files, not the asset catalog: actool keeps a decoded 16-bit copy of every HEIC next to it, 12 MB for the 40
boars instead of 2.2 MB, whatever the compression setting. A locked avatar isn't a separate picture: Android's
silhouette filter turns the opaque square into one flat color, which the view draws itself.

Usage: python3 scripts/import-truffles.py   (needs the boar-app clone next to this repo, like sync-reference.sh)
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
OUT = ROOT / "App/Resources/Boars"
HIRES = "android-native/art/icons/hires"
SIZE = 512
# sips' HEIC quality (0-100): 85 shows no difference from the WebP at 1:1 and comes to ~55 KB a boar, about its size.
QUALITY = "85"


def git(*args: str) -> bytes:
    return subprocess.run(["git", "-C", str(APP), *args], check=True, capture_output=True).stdout


def main() -> None:
    sha = (ROOT / "Fixtures/SOURCE_SHA").read_text().strip()
    ids = [icon["id"] for icon in json.loads(ROSTER.read_text())["icons"]]
    if len(ids) != len(set(ids)):
        sys.exit("duplicate ids in the roster")
    files = set(git("ls-tree", "--name-only", f"{sha}:{HIRES}").decode().split())
    missing = [i for i in ids if f"{i}.webp" not in files]
    if missing:
        sys.exit(f"no hi-res art at {sha[:8]} for: {', '.join(missing)}")

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    with tempfile.TemporaryDirectory() as tmp:
        for i in ids:
            src = Path(tmp) / f"{i}.webp"
            src.write_bytes(git("show", f"{sha}:{HIRES}/{i}.webp"))
            info = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(src)], check=True,
                                  capture_output=True, text=True).stdout.split()
            size = (info[info.index("pixelWidth:") + 1], info[info.index("pixelHeight:") + 1])
            if size != (str(SIZE), str(SIZE)):
                sys.exit(f"{i}.webp: expected {SIZE}x{SIZE}, got {size[0]}x{size[1]}")
            subprocess.run(["sips", "-s", "format", "heic", "-s", "formatOptions", QUALITY, str(src),
                            "--out", str(OUT / f"truffle_{i}.heic")], check=True, capture_output=True)
    total = sum(p.stat().st_size for p in OUT.glob("*.heic"))
    print(f"{len(ids)} boars from {sha[:8]} into {OUT.relative_to(ROOT)} ({total / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
