#!/usr/bin/env bats

INSTALL_SH="$BATS_TEST_DIRNAME/../../install.sh"
FIXTURES="$BATS_TEST_DIRNAME/../fixtures/bin"

setup() {
  export HOME
  HOME="$(mktemp -d)"
  export SHELL=/bin/bash
  export PATH="$FIXTURES:/usr/bin:/bin"
  mkdir -p "$HOME/.agent-mux/bin" "$HOME/.agent-mux/backups" "$HOME/.config/tmux"
  touch "$HOME/.agent-mux/bin/tmux-agent"
}

teardown() {
  rm -rf "$HOME"
}

@test "uninstall removes agent-mux directory" {
  run bash "$INSTALL_SH" uninstall
  [ "$status" -eq 0 ]
  [ ! -d "$HOME/.agent-mux" ]
}

@test "uninstall removes symlink" {
  echo "# conf" > "$HOME/.agent-mux/tmux.conf"
  ln -sf "$HOME/.agent-mux/tmux.conf" "$HOME/.config/tmux/tmux.conf"
  run bash "$INSTALL_SH" uninstall
  [ "$status" -eq 0 ]
  [ ! -L "$HOME/.config/tmux/tmux.conf" ]
}

@test "uninstall restores latest backup" {
  echo "# my original config" > "$HOME/.agent-mux/backups/tmux.conf.20240101-120000"
  echo "# agent-mux config"   > "$HOME/.agent-mux/tmux.conf"
  ln -sf "$HOME/.agent-mux/tmux.conf" "$HOME/.config/tmux/tmux.conf"
  run bash "$INSTALL_SH" uninstall
  [ "$status" -eq 0 ]
  grep -q "my original config" "$HOME/.config/tmux/tmux.conf"
}

@test "uninstall succeeds with no symlink present" {
  run bash "$INSTALL_SH" uninstall
  [ "$status" -eq 0 ]
}
