#!/usr/bin/env bash
# Copy this working tree to the Mac mini build host (cx) and run a command there, in the copy.
# Usage: scripts/cx.sh '<command>'     e.g. scripts/cx.sh 'swift test --scratch-path .build/cx'
# Env: CX_HOST (user@host, required), CX_KEY (ssh key, optional), CX_DIR (default Dev/boar-ios-app).
# Set them in ~/.config/boar/local.env (outside the repo): host details never go in this public repo.
# ponytail: copies tracked + untracked-unignored files and never deletes on the Mac; a file removed here
# lingers there until `scripts/cx.sh 'git clean -fdx -e Vendor -e .build'` or a fresh CX_DIR.
set -euo pipefail
[ -f ~/.config/boar/local.env ] && . ~/.config/boar/local.env
HOST="${CX_HOST:?set CX_HOST=user@host in ~/.config/boar/local.env}"; DIR="${CX_DIR:-Dev/boar-ios-app}"
cd "$(dirname "$0")/.."
SSH=(ssh ${CX_KEY:+-i "$CX_KEY"} -o ConnectTimeout=8 "$HOST")
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
