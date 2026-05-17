#!/usr/bin/env bats

TMUX_AGENT="$BATS_TEST_DIRNAME/../../scripts/tmux-agent"

setup() {
  SOCKET="$BATS_TMPDIR/tmux-submit-$BATS_TEST_NUMBER.sock"
  export XDG_RUNTIME_DIR="$BATS_TMPDIR/xdg-submit-$$-$BATS_TEST_NUMBER"
  mkdir -p "$XDG_RUNTIME_DIR"

  tmux -S "$SOCKET" new-session -d -s submit_test
  tmux -S "$SOCKET" split-window -h -t submit_test

  PANES=( $(tmux -S "$SOCKET" list-panes -t submit_test -F '#{pane_id}') )
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

@test "send exits 0 with settle disabled" {
  TMUX_AGENT_SEND_SETTLE=0 run bash "$TMUX_AGENT" send "$TARGET_PANE" "hello there"
  [ "$status" -eq 0 ]
  pane_text=$(tmux -S "$SOCKET" capture-pane -t "$TARGET_PANE" -p -J)
  [[ "$pane_text" == *"hello there"* ]]
}

@test "send completes once with verify on (no loop/hang)" {
  TMUX_AGENT_SEND_SETTLE=0 TMUX_AGENT_SEND_VERIFY=1 run bash "$TMUX_AGENT" send "$TARGET_PANE" "verify on path"
  [ "$status" -eq 0 ]
  pane_text=$(tmux -S "$SOCKET" capture-pane -t "$TARGET_PANE" -p -J)
  [[ "$pane_text" == *"verify on path"* ]]
}

@test "send exits 0 with verify disabled" {
  TMUX_AGENT_SEND_SETTLE=0 TMUX_AGENT_SEND_VERIFY=0 run bash "$TMUX_AGENT" send "$TARGET_PANE" "verify off path"
  [ "$status" -eq 0 ]
  pane_text=$(tmux -S "$SOCKET" capture-pane -t "$TARGET_PANE" -p -J)
  [[ "$pane_text" == *"verify off path"* ]]
}

@test "invalid TMUX_AGENT_SEND_SETTLE is rejected" {
  TMUX_AGENT_SEND_SETTLE=abc run bash "$TMUX_AGENT" send "$TARGET_PANE" "x"
  [ "$status" -ne 0 ]
}

@test "fractional TMUX_AGENT_SEND_SETTLE is accepted" {
  TMUX_AGENT_SEND_SETTLE=0.05 run bash "$TMUX_AGENT" send "$TARGET_PANE" "fractional settle"
  [ "$status" -eq 0 ]
}
