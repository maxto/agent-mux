#!/usr/bin/env bats

INSTALL_SH="$BATS_TEST_DIRNAME/../../install.sh"

setup() {
  SOCKET="$BATS_TMPDIR/tmux-session-bootstrap-$BATS_TEST_NUMBER.sock"
  tmux -S "$SOCKET" new-session -d -s session_bootstrap 2>/dev/null
  TEST_PANE=$(tmux -S "$SOCKET" list-panes -t session_bootstrap -F '#{pane_id}' | head -1)
  export TMUX_AGENT_SOCKET="$SOCKET"
  export TMUX_PANE="$TEST_PANE"
  unset TMUX
}

teardown() {
  tmux -S "$SOCKET" kill-server 2>/dev/null || true
  rm -f "$SOCKET"
}

@test "agent-mux session creates three labeled panes inside tmux" {
  run bash "$INSTALL_SH" session
  [ "$status" -eq 0 ]

  count=$(tmux -S "$SOCKET" list-panes -t session_bootstrap -F '#{pane_id}' | wc -l | tr -d ' ')
  [ "$count" -eq 3 ]

  labels=$(tmux -S "$SOCKET" list-panes -t session_bootstrap -F '#{@name}' | sort | tr '\n' ' ')
  [[ "$labels" == *"coordinator"* ]]
  [[ "$labels" == *"worker1"* ]]
  [[ "$labels" == *"worker2"* ]]
}

@test "agent-mux session is idempotent for existing labeled workers" {
  bash "$INSTALL_SH" session >/dev/null
  bash "$INSTALL_SH" session >/dev/null

  count=$(tmux -S "$SOCKET" list-panes -t session_bootstrap -F '#{pane_id}' | wc -l | tr -d ' ')
  [ "$count" -eq 3 ]
}

@test "agent-mux session applies custom labels inside tmux" {
  run bash "$INSTALL_SH" session --labels lead,reviewer,tester,bash
  [ "$status" -eq 0 ]

  count=$(tmux -S "$SOCKET" list-panes -t session_bootstrap -F '#{pane_id}' | wc -l | tr -d ' ')
  [ "$count" -eq 4 ]

  labels=$(tmux -S "$SOCKET" list-panes -t session_bootstrap -F '#{@name}' | sort | tr '\n' ' ')
  [[ "$labels" == *"lead"* ]]
  [[ "$labels" == *"reviewer"* ]]
  [[ "$labels" == *"tester"* ]]
  [[ "$labels" == *"bash"* ]]
}
