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

@test "global install does not install legacy help.txt" {
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.agent-mux/help.txt" ]
}

@test "global install creates tmux.conf symlink by default" {
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.config/tmux/tmux.conf" ]
}

@test "global install tmux.conf symlink points to agent-mux tmux.conf" {
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  target=$(readlink "$HOME/.config/tmux/tmux.conf")
  [ "$target" = "$HOME/.agent-mux/tmux.conf" ]
}

@test "global install --no-config skips tmux.conf symlink" {
  run bash "$INSTALL_SH" --no-config
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.config/tmux/tmux.conf" ]
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

@test "--help shows combined agent-mux and tmux-agent reference" {
  run bash "$INSTALL_SH" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: agent-mux"* ]]
  [[ "$output" == *"tmux-agent — cross-pane communication"* ]]
  [[ "$output" == *"tmux-agent send <target> <text>"* ]]
  [[ "$output" != *"pane navigation"* ]]
}

@test "help subcommand points users to --help" {
  run bash "$INSTALL_SH" help
  [ "$status" -ne 0 ]
  [[ "$output" == *"Run 'agent-mux --help' for usage."* ]]
}
