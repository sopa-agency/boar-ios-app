#!/bin/bash
# Runs llama-server for BOAR's "Mac on Your Network" engine (Settings → Advanced → Engine): on the Mac that answers,
# listening on the local network. BOAR keeps search, the library and the chats on the device; only the writing comes here.
#
#   scripts/serve-remote.sh <model.gguf> [port] [api-key]
#
# Then in BOAR: Address = <this Mac's name>.local:<port> (System Settings → General → Sharing shows the name).
# Needs a llama.cpp build with llama-server (b11010 in this workspace: spikes/llama-b11010*/bin/llama-server).
set -eu
MODEL="${1:?usage: serve-remote.sh <model.gguf> [port] [api-key]}"; PORT="${2:-8080}"; KEY="${3:-}"
SERVER="${LLAMA_SERVER:-$(command -v llama-server || true)}"
[ -x "$SERVER" ] || { echo "llama-server not found: set LLAMA_SERVER=/path/to/llama-server"; exit 1; }
ARGS=(-m "$MODEL" --jinja -c 8192 -np 1 --host 0.0.0.0 --port "$PORT")
[ -n "$KEY" ] && ARGS+=(--api-key "$KEY")
echo "BOAR remote engine on $(scutil --get LocalHostName 2>/dev/null || hostname).local:$PORT"
exec "$SERVER" "${ARGS[@]}"
