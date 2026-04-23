#!/usr/bin/env bats

TMUX_AGENT="$BATS_TEST_DIRNAME/../../scripts/tmux-agent"

setup() {
  SOCKET="$BATS_TMPDIR/tmux-test-$BATS_TEST_NUMBER.sock"
  tmux -S "$SOCKET" new-session -d -s test 2>/dev/null
  TEST_PANE=$(tmux -S "$SOCKET" list-panes -t test -F '#{pane_id}' | head -1)
  export TMUX_AGENT_SOCKET="$SOCKET"
  export TMUX_PANE="$TEST_PANE"
}

teardown() {
  tmux -S "$SOCKET" kill-server 2>/dev/null || true
  rm -f "$SOCKET"
  UID_VAL=$(id -u)
  rm -f "/tmp/tmux-agent-read-${UID_VAL}-"* 2>/dev/null || true
}

@test "list shows pane" {
  run bash "$TMUX_AGENT" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_PANE"* ]]
}

@test "name sets label on pane" {
  run bash "$TMUX_AGENT" name "$TEST_PANE" testlabel
  [ "$status" -eq 0 ]
}

@test "resolve returns pane id for label" {
  bash "$TMUX_AGENT" name "$TEST_PANE" testlabel
  run bash "$TMUX_AGENT" resolve testlabel
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_PANE" ]
}

@test "list shows label after name" {
  bash "$TMUX_AGENT" name "$TEST_PANE" myagent
  run bash "$TMUX_AGENT" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"myagent"* ]]
}

@test "resolve fails for unknown label" {
  run bash "$TMUX_AGENT" resolve nonexistentlabel
  [ "$status" -ne 0 ]
  [[ "$output" == *"no pane found"* ]]
}

@test "type accepts label as target" {
  bash "$TMUX_AGENT" name "$TEST_PANE" typetarget
  bash "$TMUX_AGENT" read typetarget
  run bash "$TMUX_AGENT" type typetarget "hello"
  [ "$status" -eq 0 ]
}

@test "version prints version string" {
  run bash "$TMUX_AGENT" version
  [ "$status" -eq 0 ]
  [[ "$output" == tmux-agent* ]]
}
