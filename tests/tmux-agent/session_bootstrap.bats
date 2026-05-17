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

current_pane_count() {
  tmux -S "$SOCKET" list-panes -t session_bootstrap -F '#{pane_id}' | wc -l | tr -d ' '
}

@test "agent-mux session without subcommand does not create panes inside tmux" {
  run bash "$INSTALL_SH" session
  [ "$status" -eq 0 ]
  [ "$(current_pane_count)" -eq 1 ]
  [[ "$output" == *"agent-mux session"* ]]
}

@test "session start from inside tmux creates a separate detached session" {
  run bash "$INSTALL_SH" session start
  [ "$status" -eq 0 ]

  # Current window is untouched.
  [ "$(current_pane_count)" -eq 1 ]

  # A new single-pane session 'agent' exists, separate from the caller's.
  tmux -S "$SOCKET" has-session -t agent
  count=$(tmux -S "$SOCKET" list-panes -t agent -F '#{pane_id}' | wc -l | tr -d ' ')
  [ "$count" -eq 1 ]
  [[ "$output" == *"Created tmux session 'agent' (1 pane)"* ]]
}

@test "session start errors if the target session already exists" {
  bash "$INSTALL_SH" session start >/dev/null
  run bash "$INSTALL_SH" session start
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
  [ "$(current_pane_count)" -eq 1 ]
}

@test "session start --labels creates a separate labeled session, current window untouched" {
  run bash "$INSTALL_SH" session start --labels lead,reviewer,tester,bash
  [ "$status" -eq 0 ]

  [ "$(current_pane_count)" -eq 1 ]

  count=$(tmux -S "$SOCKET" list-panes -t agent -F '#{pane_id}' | wc -l | tr -d ' ')
  [ "$count" -eq 4 ]

  labels=$(tmux -S "$SOCKET" list-panes -t agent -F '#{@name}' | sort | tr '\n' ' ')
  [[ "$labels" == *"lead"* ]]
  [[ "$labels" == *"reviewer"* ]]
  [[ "$labels" == *"tester"* ]]
  [[ "$labels" == *"bash"* ]]
}
