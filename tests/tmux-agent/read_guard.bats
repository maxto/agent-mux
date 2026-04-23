#!/usr/bin/env bats

TMUX_AGENT="$BATS_TEST_DIRNAME/../../scripts/tmux-agent"

setup() {
  SOCKET="$BATS_TMPDIR/tmux-test-$BATS_TEST_NUMBER.sock"
  tmux -S "$SOCKET" new-session -d -s test 2>/dev/null
  TEST_PANE=$(tmux -S "$SOCKET" list-panes -t test -F '#{pane_id}' | head -1)
  export TMUX_AGENT_SOCKET="$SOCKET"
  export TMUX_PANE="$TEST_PANE"
  UID_VAL=$(id -u)
  GUARD_FILE="/tmp/tmux-agent-read-${UID_VAL}-${TEST_PANE//%/_}"
  rm -f "$GUARD_FILE"
}

teardown() {
  tmux -S "$SOCKET" kill-server 2>/dev/null || true
  rm -f "$SOCKET"
  UID_VAL=$(id -u)
  rm -f "/tmp/tmux-agent-read-${UID_VAL}-"* 2>/dev/null || true
}

@test "type fails without prior read" {
  run bash "$TMUX_AGENT" type "$TEST_PANE" "hello"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must read the pane before interacting"* ]]
}

@test "keys fails without prior read" {
  run bash "$TMUX_AGENT" keys "$TEST_PANE" Enter
  [ "$status" -ne 0 ]
  [[ "$output" == *"must read the pane before interacting"* ]]
}

@test "type succeeds after read" {
  bash "$TMUX_AGENT" read "$TEST_PANE"
  run bash "$TMUX_AGENT" type "$TEST_PANE" "hello"
  [ "$status" -eq 0 ]
}

@test "keys succeeds after read" {
  bash "$TMUX_AGENT" read "$TEST_PANE"
  run bash "$TMUX_AGENT" keys "$TEST_PANE" Enter
  [ "$status" -eq 0 ]
}

@test "read guard clears after type — second type fails" {
  bash "$TMUX_AGENT" read "$TEST_PANE"
  bash "$TMUX_AGENT" type "$TEST_PANE" "hello"
  run bash "$TMUX_AGENT" type "$TEST_PANE" "world"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must read the pane before interacting"* ]]
}

@test "read guard clears after keys — second keys fails" {
  bash "$TMUX_AGENT" read "$TEST_PANE"
  bash "$TMUX_AGENT" keys "$TEST_PANE" Enter
  run bash "$TMUX_AGENT" keys "$TEST_PANE" Enter
  [ "$status" -ne 0 ]
}

@test "read returns pane output" {
  run bash "$TMUX_AGENT" read "$TEST_PANE" 5
  [ "$status" -eq 0 ]
}
