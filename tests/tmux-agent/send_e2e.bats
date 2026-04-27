#!/usr/bin/env bats
# End-to-end tests for cmd_send auto-spill behaviour using a real tmux server.
# Requires tmux to be installed. Tests check whether send uses file transport
# (stdout contains "thread: <id>") or inline (no "thread:" in stdout).

TMUX_AGENT="$BATS_TEST_DIRNAME/../../scripts/tmux-agent"

setup() {
  SOCKET="$BATS_TMPDIR/tmux-e2e-$$-$BATS_TEST_NUMBER.sock"
  export XDG_RUNTIME_DIR="$BATS_TMPDIR/xdg-e2e-$$-$BATS_TEST_NUMBER"
  mkdir -p "$XDG_RUNTIME_DIR"

  tmux -S "$SOCKET" new-session -d -s test
  tmux -S "$SOCKET" split-window -h -t test

  PANES=( $(tmux -S "$SOCKET" list-panes -t test -F '#{pane_id}') )
  SENDER_PANE="${PANES[0]}"
  TARGET_PANE="${PANES[1]}"

  export TMUX_AGENT_SOCKET="$SOCKET"
  export TMUX_PANE="$SENDER_PANE"
  unset TMUX_AGENT_INLINE_THRESHOLD

  UID_VAL=$(id -u)
}

teardown() {
  tmux -S "$SOCKET" kill-server 2>/dev/null || true
  rm -f "$SOCKET"
  rm -rf "$XDG_RUNTIME_DIR"
  rm -f "/tmp/tmux-agent-read-${UID_VAL}-"* 2>/dev/null || true
}

# Helper: generate a payload of exactly N chars
make_payload() {
  python3 -c "print('A' * $1, end='')"
}

# ── default threshold (2048) ──────────────────────────────────────────────────

@test "send: default threshold auto-spills payload >2048 chars (prints thread:)" {
  PAYLOAD=$(make_payload 2049)
  run bash "$TMUX_AGENT" send "$TARGET_PANE" "$PAYLOAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"thread: "* ]]
}

@test "send: default threshold keeps payload <=2048 chars inline (no thread:)" {
  PAYLOAD=$(make_payload 2048)
  run bash "$TMUX_AGENT" send "$TARGET_PANE" "$PAYLOAD"
  [ "$status" -eq 0 ]
  [[ "$output" != *"thread: "* ]]
}

# ── high threshold (4096) ─────────────────────────────────────────────────────

@test "send: threshold=4096 keeps payload between 2049-4095 inline (no thread:)" {
  PAYLOAD=$(make_payload 3000)
  TMUX_AGENT_INLINE_THRESHOLD=4096 run bash "$TMUX_AGENT" send "$TARGET_PANE" "$PAYLOAD"
  [ "$status" -eq 0 ]
  [[ "$output" != *"thread: "* ]]
}

@test "send: threshold=4096 still spills payload >4096 to file (prints thread:)" {
  PAYLOAD=$(make_payload 4097)
  TMUX_AGENT_INLINE_THRESHOLD=4096 run bash "$TMUX_AGENT" send "$TARGET_PANE" "$PAYLOAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"thread: "* ]]
}

# ── threshold=0 forces always-file ───────────────────────────────────────────

@test "send: threshold=0 forces file transport even for small payload (prints thread:)" {
  PAYLOAD=$(make_payload 100)
  TMUX_AGENT_INLINE_THRESHOLD=0 run bash "$TMUX_AGENT" send "$TARGET_PANE" "$PAYLOAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"thread: "* ]]
}

@test "send: threshold=0 forces file transport for empty payload (prints thread:)" {
  TMUX_AGENT_INLINE_THRESHOLD=0 run bash "$TMUX_AGENT" send "$TARGET_PANE" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"thread: "* ]]
}

# ── --file flag always uses file transport ────────────────────────────────────

@test "send --file: always uses file transport regardless of payload size" {
  PAYLOAD=$(make_payload 50)
  run bash "$TMUX_AGENT" send --file "$TARGET_PANE" "$PAYLOAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"thread: "* ]]
}

# ── --path streams bytes from disk (preserves trailing newlines) ──────────────

@test "send --path: thread message is byte-exact copy of source file (trailing newlines preserved)" {
  PAYLOAD_FILE="$BATS_TMPDIR/payload-path-$$"
  printf 'line1\nline2\n\n\n' > "$PAYLOAD_FILE"
  ORIG_BYTES=$(wc -c < "$PAYLOAD_FILE")

  run bash "$TMUX_AGENT" send --path "$TARGET_PANE" "$PAYLOAD_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"thread: "* ]]

  THREAD_ID=$(printf '%s' "$output" | sed -n 's/^thread: //p')
  THREAD_FILE="$XDG_RUNTIME_DIR/threads/$THREAD_ID/messages/000001.md"
  [ -f "$THREAD_FILE" ]
  COPIED_BYTES=$(wc -c < "$THREAD_FILE")
  [ "$ORIG_BYTES" = "$COPIED_BYTES" ]
  cmp "$PAYLOAD_FILE" "$THREAD_FILE"

  rm -f "$PAYLOAD_FILE"
}

@test "send --path: fails with clear error when file does not exist" {
  run bash "$TMUX_AGENT" send --path "$TARGET_PANE" "/nonexistent-path-$$.dat"
  [ "$status" -ne 0 ]
  [[ "$output" == *"file not found"* ]]
}

# ── byte-count threshold honours UTF-8 (multibyte) payloads ───────────────────

@test "send: threshold uses byte count, not char count — UTF-8 multibyte payload spills" {
  # 800 rocket emojis = 800 chars but 3200 bytes (4 bytes each in UTF-8).
  # Default threshold is 2048 bytes → must spill to file transport.
  PAYLOAD=$(python3 -c "import sys; sys.stdout.write('🚀' * 800)")
  run bash "$TMUX_AGENT" send "$TARGET_PANE" "$PAYLOAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"thread: "* ]]
}

@test "send: threshold uses byte count, not char count — UTF-8 char count alone stays inline" {
  # 500 chars, but each emoji is 4 bytes → 2000 bytes < 2048 threshold → inline.
  PAYLOAD=$(python3 -c "import sys; sys.stdout.write('🚀' * 500)")
  run bash "$TMUX_AGENT" send "$TARGET_PANE" "$PAYLOAD"
  [ "$status" -eq 0 ]
  [[ "$output" != *"thread: "* ]]
}
