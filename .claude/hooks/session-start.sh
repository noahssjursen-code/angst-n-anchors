#!/bin/bash
set -euo pipefail

# Only run in Claude Code on the web (remote) environments.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

GODOT_VERSION="4.6-stable"
GODOT_BIN="/usr/local/bin/godot"
GODOT_URL="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip"

# Idempotent: skip download if matching version already installed.
if [ -x "$GODOT_BIN" ] && "$GODOT_BIN" --version 2>/dev/null | grep -q "^4\.6\.stable"; then
  echo "Godot ${GODOT_VERSION} already installed at $GODOT_BIN"
  exit 0
fi

echo "Installing Godot ${GODOT_VERSION} headless..."

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSL -o "$TMPDIR/godot.zip" "$GODOT_URL"
unzip -q "$TMPDIR/godot.zip" -d "$TMPDIR"

install -m 0755 "$TMPDIR/Godot_v${GODOT_VERSION}_linux.x86_64" "$GODOT_BIN"

"$GODOT_BIN" --version
echo "Godot installed at $GODOT_BIN"
