#!/usr/bin/env bats

INSTALL_SH="$BATS_TEST_DIRNAME/../../install.sh"
FIXTURES="$BATS_TEST_DIRNAME/../fixtures/bin"

setup() {
  export HOME
  HOME="$(mktemp -d)"
  export SHELL=/bin/bash
  export PATH="$FIXTURES:/usr/bin:/bin"
  export TMUX_FIXTURE_LOG="$BATS_TMPDIR/tmux-session-$BATS_TEST_NUMBER.log"
  unset TMUX TMUX_PANE TMUX_AGENT_SOCKET TMUX_FIXTURE_HAS_SESSION
}

teardown() {
  rm -rf "$HOME"
  rm -f "$TMUX_FIXTURE_LOG"
}

@test "session help shows usage" {
  run bash "$INSTALL_SH" session --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"agent-mux session"* ]]
  [[ "$output" == *"--labels a,b,c"* ]]
}

@test "session outside tmux creates and attaches named session" {
  run bash "$INSTALL_SH" session --name custom
  [ "$status" -eq 0 ]
  grep -q "new-session -d -s custom -n agents" "$TMUX_FIXTURE_LOG"
  grep -q "attach-session -t custom" "$TMUX_FIXTURE_LOG"
}

@test "session outside tmux applies custom labels" {
  run bash "$INSTALL_SH" session --labels lead,reviewer,tester
  [ "$status" -eq 0 ]
  grep -q "set-option -p -t %1 @name lead" "$TMUX_FIXTURE_LOG"
  grep -q "set-option -p -t %2 @name reviewer" "$TMUX_FIXTURE_LOG"
  grep -q "set-option -p -t %3 @name tester" "$TMUX_FIXTURE_LOG"
}

@test "session outside tmux attaches existing session without modifying it" {
  export TMUX_FIXTURE_HAS_SESSION=0
  run bash "$INSTALL_SH" session --name existing
  [ "$status" -eq 0 ]
  [[ "$output" == *"already exists"* ]]
  grep -q "attach-session -t existing" "$TMUX_FIXTURE_LOG"
  ! grep -q "new-session -d -s existing" "$TMUX_FIXTURE_LOG"
}

@test "session rejects labels with wrong count" {
  run bash "$INSTALL_SH" session --labels one,two
  [ "$status" -ne 0 ]
  [[ "$output" == *"exactly three"* ]]
}

@test "session rejects trailing comma in labels" {
  run bash "$INSTALL_SH" session --labels one,two,three,
  [ "$status" -ne 0 ]
  [[ "$output" == *"exactly three"* ]]
}
