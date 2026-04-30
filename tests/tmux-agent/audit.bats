#!/usr/bin/env bats

TMUX_AGENT="$BATS_TEST_DIRNAME/../../scripts/tmux-agent"

setup() {
  SOCKET="$BATS_TMPDIR/tmux-audit-$BATS_TEST_NUMBER.sock"
  tmux -S "$SOCKET" new-session -d -s audit_test 2>/dev/null
  TEST_PANE=$(tmux -S "$SOCKET" list-panes -t audit_test -F '#{pane_id}' | head -1)
  export TMUX_AGENT_SOCKET="$SOCKET"
  export TMUX_PANE="$TEST_PANE"
  export XDG_RUNTIME_DIR="$BATS_TMPDIR/xdg-audit-$$-$BATS_TEST_NUMBER"
  mkdir -p "$XDG_RUNTIME_DIR"
}

teardown() {
  tmux -S "$SOCKET" kill-server 2>/dev/null || true
  rm -f "$SOCKET"
  rm -rf "$XDG_RUNTIME_DIR"
  uid=$(id -u)
  rm -f "/tmp/tmux-agent-read-${uid}-"* 2>/dev/null || true
}

_logfile() {
  local session
  session=$(tmux -S "$SOCKET" display-message -p '#{session_name}')
  echo "$XDG_RUNTIME_DIR/audit/${session}.jsonl"
}

@test "send creates audit log with send event" {
  bash "$TMUX_AGENT" send "$TEST_PANE" "hello audit"
  local logfile; logfile="$(_logfile)"
  [ -f "$logfile" ]
  grep -q '"event":"send"' "$logfile"
}

@test "send audit event contains required fields" {
  bash "$TMUX_AGENT" send "$TEST_PANE" "field check"
  local logfile; logfile="$(_logfile)"
  grep -q '"ts"' "$logfile"
  grep -q '"from"' "$logfile"
  grep -q '"to"' "$logfile"
  grep -q '"bytes"' "$logfile"
  grep -q '"transport"' "$logfile"
}

@test "thread send creates thread_create and send events" {
  export TMUX_AGENT_INLINE_THRESHOLD=0
  bash "$TMUX_AGENT" send "$TEST_PANE" "thread payload"
  local logfile; logfile="$(_logfile)"
  grep -q '"event":"thread_create"' "$logfile"
  grep -q '"transport":"thread"' "$logfile"
}

@test "audit tail prints recent events" {
  bash "$TMUX_AGENT" send "$TEST_PANE" "hello for tail"
  run bash "$TMUX_AGENT" audit tail 5
  [ "$status" -eq 0 ]
  [[ "$output" == *"send"* ]]
}

@test "audit tail with no log shows friendly message" {
  run bash "$TMUX_AGENT" audit tail
  [ "$status" -eq 0 ]
  [[ "$output" == *"no audit log"* ]]
}

@test "audit stats shows counters" {
  bash "$TMUX_AGENT" send "$TEST_PANE" "stats test"
  run bash "$TMUX_AGENT" audit stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"sends:"* ]]
  [[ "$output" == *"inline_bytes:"* ]]
  [[ "$output" == *"thread_bytes:"* ]]
  [[ "$output" == *"thread_read_bytes:"* ]]
}

@test "audit stats separates inline, thread, and thread read bytes" {
  bash "$TMUX_AGENT" send "$TEST_PANE" "inline"
  export TMUX_AGENT_INLINE_THRESHOLD=0
  run bash "$TMUX_AGENT" send "$TEST_PANE" "thread-payload"
  [ "$status" -eq 0 ]
  local thread_id
  thread_id=$(printf '%s' "$output" | sed -n 's/^thread: //p')
  [ -n "$thread_id" ]

  bash "$TMUX_AGENT" thread read "$thread_id" >/dev/null

  run bash "$TMUX_AGENT" audit stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"inline_bytes:       6"* ]]
  [[ "$output" == *"thread_bytes:       14"* ]]
  [[ "$output" == *"thread_read_bytes:  14"* ]]
}

@test "pause and resume events are logged" {
  bash "$TMUX_AGENT" pause "audit test"
  bash "$TMUX_AGENT" resume
  local logfile; logfile="$(_logfile)"
  grep -q '"event":"pause"' "$logfile"
  grep -q '"event":"resume"' "$logfile"
}
