#!/usr/bin/env bats

INSTALL_SH="$BATS_TEST_DIRNAME/../../install.sh"
FIXTURES="$BATS_TEST_DIRNAME/../fixtures/bin"

setup() {
  export HOME
  HOME="$(mktemp -d)"
  export SHELL=/bin/bash
  export PATH="$FIXTURES:/usr/bin:/bin"
}

teardown() {
  rm -rf "$HOME"
}

@test "global install creates bin directory" {
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  [ -d "$HOME/.agent-mux/bin" ]
}

@test "global install places tmux-agent binary" {
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  [ -x "$HOME/.agent-mux/bin/tmux-agent" ]
}

@test "global install places agent-mux binary" {
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  [ -x "$HOME/.agent-mux/bin/agent-mux" ]
}

@test "global install places help.txt" {
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.agent-mux/help.txt" ]
}

@test "global install adds agent-mux bin to .bashrc" {
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  grep -q '.agent-mux/bin' "$HOME/.bashrc"
}

@test "global install does not add PATH twice if already present" {
  echo 'export PATH="$HOME/.agent-mux/bin:$PATH"' >> "$HOME/.bashrc"
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  count=$(grep -c '.agent-mux/bin' "$HOME/.bashrc")
  [ "$count" -eq 1 ]
}
