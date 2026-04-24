#!/usr/bin/env bash
# demo.sh — deterministic agent-mux demo
#
# Default: prints step-by-step output to stdout (useful for testing/reading).
# --attach:  types commands into the coordinator pane and attaches so the full
#            3-pane tmux UI is visible — use this mode when recording with asciinema.
#
# Usage:
#   bash demo.sh              # script-output mode (no tmux UI)
#   bash demo.sh --attach     # multi-pane visual mode (attach to session)
set -euo pipefail

DEMO_SESSION="agent-mux-demo"
DEMO_SOCKET="/tmp/tmux-agent-mux-demo-$$.sock"
TMUX_AGENT="${HOME}/.agent-mux/bin/tmux-agent"
ATTACH=false
[[ "${1:-}" == "--attach" ]] && ATTACH=true

# ── helpers ──────────────────────────────────────────────────────────────────

step() { printf '\n\033[1;34m── %s\033[0m\n' "$*"; }
cmd()  { printf '\033[0;32m$ %s\033[0m\n' "$*"; }
note() { printf '\033[0;33m   %s\033[0m\n' "$*"; }
reply(){ printf '   \033[0;36m%s\033[0m\n' "$*"; }
nl()   { echo ""; }

tmx() { tmux -S "$DEMO_SOCKET" "$@"; }

PAYLOAD_FILE=""  # set later; declared here so trap can clean it up on interrupt
cleanup() {
  tmx kill-server 2>/dev/null || true
  rm -f "$DEMO_SOCKET"
  [[ -n "$PAYLOAD_FILE" ]] && rm -f "$PAYLOAD_FILE"
}
trap cleanup EXIT

# ── check deps ───────────────────────────────────────────────────────────────

for dep in tmux python3; do
  command -v "$dep" >/dev/null 2>&1 || { echo "error: $dep not found" >&2; exit 1; }
done
[[ -x "$TMUX_AGENT" ]] || {
  echo "error: tmux-agent not found at $TMUX_AGENT" >&2
  echo "Install: curl -fsSL https://maxto.github.io/agent-mux/install.sh | bash" >&2
  exit 1
}

# ── session setup ─────────────────────────────────────────────────────────────

tmx new-session  -d -s "$DEMO_SESSION" -x 200 -y 50
tmx split-window -h -t "$DEMO_SESSION"
tmx split-window -v -t "$DEMO_SESSION":0.1
tmx select-layout -t "$DEMO_SESSION" tiled

PANES=( $(tmx list-panes -t "$DEMO_SESSION" -F '#{pane_id}') )
COORD="${PANES[0]}"
CODEX="${PANES[1]}"
GEMINI="${PANES[2]}"

export TMUX_AGENT_SOCKET="$DEMO_SOCKET"
export TMUX_PANE="$COORD"

"$TMUX_AGENT" name "$COORD"  coordinator
"$TMUX_AGENT" name "$CODEX"  codex
"$TMUX_AGENT" name "$GEMINI" gemini

# Initialise worker panes with labelled prompts
tmx send-keys -t "$CODEX"  "PS1='[codex]\$ '; clear" Enter
tmx send-keys -t "$GEMINI" "PS1='[gemini]\$ '; clear" Enter
sleep 0.3

# ── large payload (written to a temp file so the coordinator pane can read it) ─

PAYLOAD_FILE=$(mktemp /tmp/agent-mux-demo-payload-XXXXXX.txt)
python3 -c "
lines = ['diff --git a/src/auth.ts b/src/auth.ts', '--- a/src/auth.ts', '+++ b/src/auth.ts']
for i in range(1, 120):
    lines.append(f'+  // line {i}: ' + 'x' * 60)
print('\n'.join(lines))
" > "$PAYLOAD_FILE"
PAYLOAD_SIZE=$(wc -c < "$PAYLOAD_FILE" | tr -d ' ')

# ── attach mode: drive via keystrokes into coordinator pane ──────────────────

if $ATTACH; then
  # Driver runs in background; tmux attach blocks in the foreground so
  # asciinema records the multi-pane tmux UI.
  (
    sleep 1.5   # let tmux attach initialise before typing starts

    type_in() {   # type a command into coordinator pane
      tmx send-keys -t "$COORD" "$1" Enter
      sleep "${2:-1}"
    }

    # Set env inside coordinator pane so tmux-agent commands work there
    type_in "export TMUX_AGENT_SOCKET='$DEMO_SOCKET' TMUX_PANE='$COORD' PATH='$HOME/.agent-mux/bin:\$PATH'" 0.3
    type_in "clear" 0.3

    type_in "# Step 1: discover panes" 0.3
    type_in "tmux-agent list" 2

    type_in "# Step 2: coordinator → codex (no copy-paste)" 0.3
    type_in "tmux-agent send codex 'Please review src/auth.ts and report coverage'" 1.5
    type_in "echo '  [from:codex] 87% line coverage. OAuth refresh path (L142-168) untested.'" 1.5

    type_in "# Step 3: coordinator → gemini (adversarial review)" 0.3
    type_in "tmux-agent send gemini 'Adversarial review: any security issues in the auth flow?'" 1.5
    type_in "echo '  [from:gemini] Token fixation risk in session renewal. Rotate session ID on escalation.'" 1.5

    type_in "# Step 4: large payload via thread transport" 0.3
    type_in "tmux-agent send --file codex \"\$(cat '$PAYLOAD_FILE')\"   # ${PAYLOAD_SIZE} bytes" 2
    type_in "echo '  codex received only a compact ping — full diff stays on disk until thread read'" 2

    type_in "echo '=== demo complete ==='" 0.5
    sleep 2
    rm -f "$PAYLOAD_FILE"
    tmx kill-server 2>/dev/null || true
  ) &
  DRIVER_PID=$!

  tmx attach -t "$DEMO_SESSION"   # blocks; asciinema records this view
  wait "$DRIVER_PID" 2>/dev/null || true
  exit 0
fi

# ── script-output mode (default, no attach) ──────────────────────────────────

step "Setting up demo session"
note "Session: $DEMO_SESSION  |  Panes: coordinator / codex / gemini"

step "Step 1 — Discover panes"
cmd "tmux-agent list"
"$TMUX_AGENT" list
sleep 1

step "Step 2 — Coordinator → codex (cross-pane, no copy-paste)"
cmd "tmux-agent send codex 'Please review src/auth.ts and report coverage'"
"$TMUX_AGENT" send "$CODEX" "Please review src/auth.ts and report coverage" >/dev/null
note "Message delivered. Mock response:"
reply "[from:codex] 87% line coverage. OAuth refresh path (lines 142-168) untested."
sleep 1

step "Step 3 — Coordinator → gemini (adversarial review)"
cmd "tmux-agent send gemini 'Adversarial review: any security issues in the auth flow?'"
"$TMUX_AGENT" send "$GEMINI" "Adversarial review: any security issues in the auth flow?" >/dev/null
note "Mock response:"
reply "[from:gemini] Token fixation risk in session renewal. Recommend rotating session ID on privilege escalation."
sleep 1

step "Step 4 — Large payload via thread transport (no prompt bloat)"
cmd "tmux-agent send --file codex \"\$(cat payload.txt)\"   # ${PAYLOAD_SIZE} bytes"
THREAD_OUT=$("$TMUX_AGENT" send --file "$CODEX" "$(cat "$PAYLOAD_FILE")" 2>/dev/null)
THREAD_ID=$(echo "$THREAD_OUT" | grep '^thread: ' | sed 's/^thread: //')
echo "thread: $THREAD_ID"
note "codex received only a compact ping (~114 chars) — full ${PAYLOAD_SIZE}-byte diff stays on disk."
note "codex loads it only when needed:  tmux-agent thread read ${THREAD_ID}"

nl
printf '\033[1;32m=== demo complete ===\033[0m\n'
nl
echo "  ✓ 3-pane session — coordinator / codex / gemini"
echo "  ✓ Cross-pane messaging without copy-paste"
echo "  ✓ Thread transport: ${PAYLOAD_SIZE}-byte payload → 114-char ping"
nl

rm -f "$PAYLOAD_FILE"
