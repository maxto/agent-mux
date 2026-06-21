#!/usr/bin/env bats
# Tests for 'tmux-agent split' — sanctioned pane creation in a live window.
# Requires a real tmux server.

TMUX_AGENT="$BATS_TEST_DIRNAME/../../scripts/tmux-agent"

setup() {
  SOCKET="$BATS_TMPDIR/tmux-split-$BATS_TEST_NUMBER.sock"
  export XDG_RUNTIME_DIR="$BATS_TMPDIR/xdg-split-$$-$BATS_TEST_NUMBER"
  mkdir -p "$XDG_RUNTIME_DIR"

  tmux -S "$SOCKET" new-session -d -s split_test
  TEST_PANE=$(tmux -S "$SOCKET" list-panes -t split_test -F '#{pane_id}' | head -1)

  export TMUX_AGENT_SOCKET="$SOCKET"
  export TMUX_PANE="$TEST_PANE"
  unset TMUX
}

teardown() {
  tmux -S "$SOCKET" kill-server 2>/dev/null || true
  rm -f "$SOCKET"
  rm -rf "$XDG_RUNTIME_DIR"
}

win0_pane_count() {
  tmux -S "$SOCKET" list-panes -t split_test:0 -F '#{pane_id}' | wc -l | tr -d ' '
}

@test "split creates a pane and prints a valid pane-id" {
  run bash "$TMUX_AGENT" split
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^%[0-9]+$ ]]
  [ "$(win0_pane_count)" -eq 2 ]
}

@test "new pane is in the same window as the caller" {
  run bash "$TMUX_AGENT" split
  [ "$status" -eq 0 ]
  new_pane="$output"
  new_win=$(tmux -S "$SOCKET" display-message -t "$new_pane" -p '#{window_id}')
  caller_win=$(tmux -S "$SOCKET" display-message -t "$TEST_PANE" -p '#{window_id}')
  [ "$new_win" = "$caller_win" ]
}

@test "--cwd sets the new pane's working directory" {
  CWD_DIR="$BATS_TMPDIR/split-cwd-$$"
  mkdir -p "$CWD_DIR"
  run bash "$TMUX_AGENT" split --cwd "$CWD_DIR"
  [ "$status" -eq 0 ]
  new_pane="$output"
  path=$(tmux -S "$SOCKET" display-message -t "$new_pane" -p '#{pane_current_path}')
  [ "$(cd "$path" && pwd -P)" = "$(cd "$CWD_DIR" && pwd -P)" ]
}

@test "-v creates a vertically stacked pane (below the caller)" {
  run bash "$TMUX_AGENT" split -v
  [ "$status" -eq 0 ]
  new_pane="$output"
  pane_top=$(tmux -S "$SOCKET" display-message -t "$new_pane" -p '#{pane_top}')
  [ "$pane_top" -gt 0 ]
}

@test "--target splits the named window, leaving the current window untouched" {
  tmux -S "$SOCKET" new-window -t split_test
  run bash "$TMUX_AGENT" split --target split_test:1
  [ "$status" -eq 0 ]
  target_count=$(tmux -S "$SOCKET" list-panes -t split_test:1 -F '#{pane_id}' | wc -l | tr -d ' ')
  [ "$target_count" -eq 2 ]
  [ "$(win0_pane_count)" -eq 1 ]
}

@test "split outside tmux without --target errors" {
  unset TMUX_PANE
  run bash "$TMUX_AGENT" split
  [ "$status" -ne 0 ]
  [[ "$output" == *"--target"* ]]
}
