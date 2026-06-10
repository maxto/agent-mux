#!/usr/bin/env bats
# Tests for 'tmux-agent kill' — destructive pane teardown.
# Requires a real tmux server.

TMUX_AGENT="$BATS_TEST_DIRNAME/../../scripts/tmux-agent"

setup() {
  SOCKET="$BATS_TMPDIR/tmux-kill-$BATS_TEST_NUMBER.sock"
  export XDG_RUNTIME_DIR="$BATS_TMPDIR/xdg-kill-$$-$BATS_TEST_NUMBER"
  mkdir -p "$XDG_RUNTIME_DIR"

  tmux -S "$SOCKET" new-session -d -s kill_test
  tmux -S "$SOCKET" split-window -h -t kill_test

  PANES=( $(tmux -S "$SOCKET" list-panes -t kill_test -F '#{pane_id}') )
  SENDER_PANE="${PANES[0]}"
  TARGET_PANE="${PANES[1]}"

  export TMUX_AGENT_SOCKET="$SOCKET"
  export TMUX_PANE="$SENDER_PANE"
  UID_VAL=$(id -u)
}

teardown() {
  tmux -S "$SOCKET" kill-server 2>/dev/null || true
  rm -f "$SOCKET"
  rm -rf "$XDG_RUNTIME_DIR"
  rm -f "/tmp/tmux-agent-read-${UID_VAL}-"* 2>/dev/null || true
}

pane_count() {
  tmux -S "$SOCKET" list-panes -t kill_test -F '#{pane_id}' | wc -l | tr -d ' '
}

@test "kill requires a target" {
  run bash "$TMUX_AGENT" kill
  [ "$status" -ne 0 ]
}

@test "kill fails without a prior read" {
  run bash "$TMUX_AGENT" kill "$TARGET_PANE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must read the pane before interacting"* ]]
  [ "$(pane_count)" -eq 2 ]
}

@test "kill removes the pane after read" {
  bash "$TMUX_AGENT" read "$TARGET_PANE" >/dev/null
  run bash "$TMUX_AGENT" kill "$TARGET_PANE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"killed pane: $TARGET_PANE"* ]]
  [ "$(pane_count)" -eq 1 ]
  remaining=$(tmux -S "$SOCKET" list-panes -t kill_test -F '#{pane_id}')
  [ "$remaining" = "$SENDER_PANE" ]
}

@test "kill resolves a label target" {
  bash "$TMUX_AGENT" name "$TARGET_PANE" victim
  bash "$TMUX_AGENT" read victim >/dev/null
  run bash "$TMUX_AGENT" kill victim
  [ "$status" -eq 0 ]
  [ "$(pane_count)" -eq 1 ]
}

@test "kill is blocked when paused" {
  bash "$TMUX_AGENT" read "$TARGET_PANE" >/dev/null
  bash "$TMUX_AGENT" pause "teardown freeze"
  run bash "$TMUX_AGENT" kill "$TARGET_PANE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"paused"* ]]
  [ "$(pane_count)" -eq 2 ]
}

@test "kill clears the read guard for the target" {
  bash "$TMUX_AGENT" read "$TARGET_PANE" >/dev/null
  bash "$TMUX_AGENT" kill "$TARGET_PANE"
  GUARD="/tmp/tmux-agent-read-${UID_VAL}-${TARGET_PANE//%/_}"
  [ ! -f "$GUARD" ]
}

@test "kill writes an audit event" {
  bash "$TMUX_AGENT" read "$TARGET_PANE" >/dev/null
  bash "$TMUX_AGENT" kill "$TARGET_PANE"
  session=$(tmux -S "$SOCKET" display-message -t "$SENDER_PANE" -p '#{session_name}')
  logfile="$XDG_RUNTIME_DIR/audit/${session}.jsonl"
  [ -f "$logfile" ]
  grep -q '"event":"kill"' "$logfile"
}

@test "kill fails on an unresolvable label" {
  run bash "$TMUX_AGENT" kill nonexistentlabel
  [ "$status" -ne 0 ]
  [[ "$output" == *"no pane found"* ]]
  [ "$(pane_count)" -eq 2 ]
}
