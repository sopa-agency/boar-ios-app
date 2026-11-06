#!/usr/bin/env bash
# Copy this working tree to the Mac build host and run a command there, in the copy.
# Usage: scripts/build-host.sh '<command>'     e.g. scripts/build-host.sh 'swift test --scratch-path .build/host'
# Env: BUILD_HOST (user@host, required), BUILD_KEY (ssh key, optional), BUILD_DIR (default Dev/boar-ios-app).
# Set them in ~/.config/boar/local.env (outside the repo): host details never go in this public repo.
# ponytail: copies tracked + untracked-unignored files and never deletes on the Mac; a file removed here
# lingers there until `scripts/build-host.sh 'git clean -fdx -e Vendor -e .build'` or a fresh BUILD_DIR.
set -euo pipefail
[ -f ~/.config/boar/local.env ] && . ~/.config/boar/local.env
HOST="${BUILD_HOST:?set BUILD_HOST=user@host in ~/.config/boar/local.env}"; DIR="${BUILD_DIR:-Dev/boar-ios-app}"
cd "$(dirname "$0")/.."
SSH=(ssh ${BUILD_KEY:+-i "$BUILD_KEY"} -o ConnectTimeout=8 "$HOST")
# Since 2026-11-04 the build host holds a real git clone that the Boar iOS agent edits: never copy over it, only run the command.
if "${SSH[@]}" "test -d $DIR/.git"; then
  echo "build-host.sh: $DIR on the build host is a git clone; not copying (push here, then pull there)" >&2
else
  git ls-files -co --exclude-standard -z | tar --null -T - -czf - | "${SSH[@]}" "mkdir -p $DIR && tar -xzf - -C $DIR"
fi
"${SSH[@]}" bash -s <<REMOTE
export PATH=/opt/homebrew/bin:\$PATH
X=\$(ls -d /Applications/Xcode-27*.app/Contents/Developer 2>/dev/null | head -1); [ -n "\$X" ] && export DEVELOPER_DIR="\$X"
cd $DIR && $*
REMOTE
