#!/usr/bin/env bash
# Copy this working tree to the Mac mini build host (cx) and run a command there, in the copy.
# Usage: scripts/cx.sh '<command>'     e.g. scripts/cx.sh 'swift test --scratch-path .build/cx'
# Env: CX_HOST (bielcx@10.0.10.226, home LAN only), CX_KEY (~/.ssh/id_ed25519_cx), CX_DIR (Dev/boar-ios-app).
# ponytail: copies tracked + untracked-unignored files and never deletes on the Mac; a file removed here
# lingers there until `scripts/cx.sh 'git clean -fdx -e Vendor -e .build'` or a fresh CX_DIR.
set -euo pipefail
HOST="${CX_HOST:-bielcx@10.0.10.226}"; KEY="${CX_KEY:-$HOME/.ssh/id_ed25519_cx}"; DIR="${CX_DIR:-Dev/boar-ios-app}"
cd "$(dirname "$0")/.."
SSH=(ssh -i "$KEY" -o ConnectTimeout=8 "$HOST")
# Since 2026-11-04 cx holds a real git clone that the Boar iOS agent edits: never copy over it, only run the command.
if "${SSH[@]}" "test -d $DIR/.git"; then
  echo "cx.sh: $DIR on cx is a git clone; not copying (push here, then pull there)" >&2
else
  git ls-files -co --exclude-standard -z | tar --null -T - -czf - | "${SSH[@]}" "mkdir -p $DIR && tar -xzf - -C $DIR"
fi
"${SSH[@]}" bash -s <<REMOTE
export PATH=/opt/homebrew/bin:\$PATH
X=\$(ls -d /Applications/Xcode-27*.app/Contents/Developer 2>/dev/null | head -1); [ -n "\$X" ] && export DEVELOPER_DIR="\$X"
cd $DIR && $*
REMOTE
