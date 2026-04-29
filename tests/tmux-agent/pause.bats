#!/usr/bin/env bats

TMUX_AGENT="$BATS_TEST_DIRNAME/../../scripts/tmux-agent"

setup() {
  SOCKET="$BATS_TMPDIR/tmux-pause-$BATS_TEST_NUMBER.sock"
  tmux -S "$SOCKET" new-session -d -s pause_test 2>/dev/null
  TEST_PANE=$(tmux -S "$SOCKET" list-panes -t pause_test -F '#{pane_id}' | head -1)
  export TMUX_AGENT_SOCKET="$SOCKET"
  export TMUX_PANE="$TEST_PANE"
  export XDG_RUNTIME_DIR="$BATS_TMPDIR/xdg-pause-$$-$BATS_TEST_NUMBER"
  mkdir -p "$XDG_RUNTIME_DIR"
}

teardown() {
  tmux -S "$SOCKET" kill-server 2>/dev/null || true
  rm -f "$SOCKET"
  rm -rf "$XDG_RUNTIME_DIR"
  uid=$(id -u)
  rm -f "/tmp/tmux-agent-read-${uid}-"* 2>/dev/null || true
}

@test "pause creates flag file" {
  run bash "$TMUX_AGENT" pause "testing"
  [ "$status" -eq 0 ]
  [ -f "$XDG_RUNTIME_DIR/PAUSED" ]
  grep -q "reason=testing" "$XDG_RUNTIME_DIR/PAUSED"
}

@test "send is blocked when paused" {
  bash "$TMUX_AGENT" pause
  run bash "$TMUX_AGENT" send "$TEST_PANE" "hello"
  [ "$status" -ne 0 ]
  [[ "$output" == *"paused"* ]]
}

@test "type is blocked when paused" {
  bash "$TMUX_AGENT" pause
  bash "$TMUX_AGENT" read "$TEST_PANE" >/dev/null
  run bash "$TMUX_AGENT" type "$TEST_PANE" "hello"
  [ "$status" -ne 0 ]
  [[ "$output" == *"paused"* ]]
}

@test "read still works when paused" {
  bash "$TMUX_AGENT" pause
  run bash "$TMUX_AGENT" read "$TEST_PANE"
  [ "$status" -eq 0 ]
}

@test "resume removes flag file and unblocks send" {
  bash "$TMUX_AGENT" pause
  [ -f "$XDG_RUNTIME_DIR/PAUSED" ]
  bash "$TMUX_AGENT" resume
  [ ! -f "$XDG_RUNTIME_DIR/PAUSED" ]
  run bash "$TMUX_AGENT" send "$TEST_PANE" "hello after resume"
  [ "$status" -eq 0 ]
}

@test "status shows PAUSED state with metadata" {
  bash "$TMUX_AGENT" pause "unit test"
  run bash "$TMUX_AGENT" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"PAUSED"* ]]
  [[ "$output" == *"reason=unit test"* ]]
}

@test "status shows running when not paused" {
  run bash "$TMUX_AGENT" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"running"* ]]
}
