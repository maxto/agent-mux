#!/usr/bin/env bash
# record.sh — record the agent-mux demo with asciinema
# Uses demo.sh --attach so the recording captures the full 3-pane tmux layout.
# Produces examples/demo-recording/assets/demo.cast and optionally demo.gif (requires agg).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$SCRIPT_DIR/assets"
CAST="$ASSETS_DIR/demo.cast"
GIF="$ASSETS_DIR/demo.gif"

# ── check asciinema ──────────────────────────────────────────────────────────

if ! command -v asciinema >/dev/null 2>&1; then
  echo "error: asciinema not found." >&2
  echo "" >&2
  echo "Install:" >&2
  echo "  Linux/WSL2:  pip install asciinema  OR  sudo apt install asciinema" >&2
  echo "  macOS:       brew install asciinema" >&2
  exit 1
fi

mkdir -p "$ASSETS_DIR"

# ── record ───────────────────────────────────────────────────────────────────
# demo.sh --attach creates the tmux session, attaches so the full pane layout
# is visible, then drives all panes with scripted keystrokes — asciinema
# records that multi-pane view.

echo "[record.sh] Recording demo → $CAST"
asciinema rec --overwrite --title "agent-mux demo" "$CAST" -- bash "$SCRIPT_DIR/demo.sh" --attach

echo "[record.sh] Cast saved: $CAST"

# ── gif (optional) ───────────────────────────────────────────────────────────

if command -v agg >/dev/null 2>&1; then
  echo "[record.sh] Generating GIF → $GIF"
  agg "$CAST" "$GIF"
  echo "[record.sh] GIF saved: $GIF"
else
  echo ""
  echo "  tip: install 'agg' to convert the cast to a GIF:"
  echo "    cargo install --git https://github.com/asciinema/agg"
  echo "  then run: agg \"$CAST\" \"$GIF\""
fi

echo ""
echo "  Play locally:  asciinema play \"$CAST\""
echo "  Upload cast:   asciinema upload \"$CAST\""
