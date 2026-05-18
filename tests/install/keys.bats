#!/usr/bin/env bats

INSTALL_SH="$BATS_TEST_DIRNAME/../../install.sh"

@test "keys prints the keyboard shortcuts table" {
  run bash "$INSTALL_SH" keys
  [ "$status" -eq 0 ]
  [[ "$output" == *"Keyboard shortcuts (agent-mux tmux config)"* ]]
  [[ "$output" == *"Alt+i/k/j/l"* ]]
  [[ "$output" == *"Alt+Tab"* ]]
  [[ "$output" == *"new window"* ]]
}

@test "controls is an alias for keys" {
  run bash "$INSTALL_SH" controls
  [ "$status" -eq 0 ]
  [[ "$output" == *"Keyboard shortcuts (agent-mux tmux config)"* ]]
}

@test "keys is listed in the CLI reference" {
  run bash "$INSTALL_SH" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"keys"* ]]
  [[ "$output" == *"Show keyboard shortcuts"* ]]
}
